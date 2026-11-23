defmodule Regents.Autolaunch.ChainWatch do
  @moduledoc """
  Every minute (`config :autolaunch, Oban, cron:`), makes sure each chain
  reading has its job: every auction's market (`Regents.Autolaunch.AuctionMarket`), new
  Robinhood launches (`Regents.Autolaunch.Robinhood.Discovery`), every listed auction's
  bids (`Regents.Autolaunch.AuctionActivity`), every listed token's trades
  (`Regents.Autolaunch.TokenTrades`) and, while covered calls are on, each covered-call
  market's sales (`Regents.Autolaunch.CoveredCalls.Sales`). A reading job is unique
  while it is incomplete, so inserting it again leaves a waiting or running one
  alone; a new auction or token is read within a minute of being listed.

  Each reader brings its jobs forward when a person's on-chain press lands
  (`Regents.Autolaunch.ChainRefresh`) through `soon/1`.
  """
  use Oban.Worker, queue: :autolaunch_default, max_attempts: 1

  alias Regents.Autolaunch.{AuctionActivity, AuctionMarket, TokenTrades}
  alias Regents.Autolaunch.CoveredCalls.Sales
  alias Regents.Autolaunch.Robinhood.Discovery
  alias Regents.Chain.Refresh, as: ChainRefresh
  alias Regents.ProductActivity

  @impl Oban.Worker
  def perform(%Oban.Job{} = job) do
    if ProductActivity.cron_allowed?(:autolaunch, job) do
      (AuctionMarket.jobs() ++
         Discovery.jobs() ++ AuctionActivity.jobs() ++ TokenTrades.jobs() ++ Sales.jobs())
      |> Enum.each(&Oban.insert!/1)
    end

    :ok
  end

  @doc """
  Makes sure the reading job `changeset` describes exists, and brings it forward
  to the ten-second gap (`ChainRefresh.gap_s/0`) when it waits longer. A job due
  sooner, or running, keeps its time, so presses that keep coming never put the
  read off.
  """
  @spec soon(Ecto.Changeset.t()) :: :ok
  def soon(changeset) do
    soon = DateTime.add(DateTime.utc_now(), ChainRefresh.gap_s())
    changeset |> Oban.insert!() |> bring_forward(soon)
  end

  defp bring_forward(%Oban.Job{state: state, scheduled_at: at} = job, soon)
       when state in ["scheduled", "retryable"] do
    if DateTime.after?(at, soon), do: {:ok, _job} = Oban.update_job(job, %{scheduled_at: soon})
    :ok
  end

  defp bring_forward(%Oban.Job{}, _soon), do: :ok
end
