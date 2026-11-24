defmodule Regents.Patchbay.Offers.Watch do
  @moduledoc """
  Every five minutes, if a market is configured, makes sure the market has its
  reading job (`Regents.Patchbay.Offers.ReadMarket`). After a person's purchase or
  claim lands, `refresh/0` brings that job forward, so the page shows it soon.
  """

  use Oban.Worker, queue: :patchbay_default, max_attempts: 1

  alias Regents.Chain.Refresh
  alias Regents.Patchbay.Offers
  alias Regents.Patchbay.Offers.ReadMarket

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    if Offers.enabled?(), do: Oban.insert!(job())
    :ok
  end

  @doc """
  Brings the market's next read to ten seconds from now, unless it was already
  due sooner, so presses that keep coming never put the read off.
  """
  @spec refresh() :: :ok | {:error, term()}
  def refresh do
    if Offers.enabled?(), do: Refresh.soon(job()), else: :ok
  end

  defp job,
    do: ReadMarket.new(%{chain_id: Offers.chain().chain_id, market: Offers.market()})
end
