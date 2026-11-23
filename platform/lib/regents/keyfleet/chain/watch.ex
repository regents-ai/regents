defmodule Regents.Keyfleet.Chain.Watch do
  @moduledoc """
  Every five minutes (`config :regents, Oban, cron:`): makes sure each deployed
  fleet has a `Regents.Keyfleet.Chain.ReadFleet` job reading its history,
  through the site's one Base read endpoint, and queues a
  `Regents.Keyfleet.Chain.ReadBalances` reading of its balances. A fleet recorded
  while the site runs is read from the next turn on, or sooner when a
  person's on-chain press lands (`refresh/1`).
  """
  use Oban.Worker, queue: :keyfleet_default, max_attempts: 1

  @behaviour Regents.Chain.Refresh

  alias Regents.Chain.Refresh, as: ChainRefresh
  alias Regents.Keyfleet.Chain.ReadBalances
  alias Regents.Keyfleet.Chain.ReadFleet

  @impl Oban.Worker
  def perform(%Oban.Job{} = job) do
    if Regents.ProductActivity.cron_allowed?(:keyfleet, job) do
      Regents.Keyfleet.Fleets.list_deployed_fleets!()
      |> Enum.flat_map(&[ReadFleet.new(%{fleet_id: &1.id}), ReadBalances.new(%{fleet_id: &1.id})])
      |> Enum.each(&Oban.insert!/1)
    end

    :ok
  end

  @doc """
  A person's on-chain press on chain `chain_id` landed: each fleet deployed on
  it reads its history ten seconds from now, instead of at its next turn, and
  its balances at once. A history read already under way is left to finish.
  """
  @impl ChainRefresh
  def refresh(chain_id) do
    soon = DateTime.add(DateTime.utc_now(), ChainRefresh.gap_s())

    Regents.Keyfleet.Fleets.list_deployed_fleets!()
    |> Enum.filter(&(&1.chain_id == chain_id))
    |> Enum.each(fn fleet ->
      %{fleet_id: fleet.id} |> ReadFleet.new() |> Oban.insert!() |> bring_forward(soon)
      Oban.insert!(ReadBalances.new(%{fleet_id: fleet.id}))
    end)
  end

  # A waiting history read due later than `soon` moves to `soon`; one due
  # sooner keeps its time, so presses that keep coming never put the read off.
  defp bring_forward(%Oban.Job{state: state, scheduled_at: at} = job, soon)
       when state in ["scheduled", "retryable"] do
    if DateTime.after?(at, soon), do: {:ok, _job} = Oban.update_job(job, %{scheduled_at: soon})
    :ok
  end

  defp bring_forward(%Oban.Job{}, _soon), do: :ok
end
