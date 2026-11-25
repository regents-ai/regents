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
    for fleet <- Regents.Keyfleet.Fleets.list_deployed_fleets!() do
      Oban.insert!(ReadFleet.new(%{fleet_id: fleet.id}))

      if Regents.ProductActivity.cron_allowed?(:keyfleet, job) do
        Oban.insert!(ReadBalances.new(%{fleet_id: fleet.id}))
      end
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
    Regents.Keyfleet.Fleets.list_deployed_fleets!()
    |> Enum.filter(&(&1.chain_id == chain_id))
    |> Enum.reduce_while(:ok, fn fleet, :ok ->
      with :ok <- ChainRefresh.soon(ReadFleet.new(%{fleet_id: fleet.id})),
           {:ok, _job} <- Oban.insert(ReadBalances.new(%{fleet_id: fleet.id})) do
        {:cont, :ok}
      else
        {:error, _reason} = failure -> {:halt, failure}
      end
    end)
  end
end
