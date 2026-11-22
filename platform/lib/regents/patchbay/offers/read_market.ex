defmodule Regents.Patchbay.Offers.ReadMarket do
  @moduledoc """
  Keeps the record of Patchbay's market current. Each run is one
  `Regents.Patchbay.Offers.Scanner` pass; the job then waits five minutes and runs
  again. `Regents.Patchbay.Offers.Watch.refresh/0` brings the next run forward to ten
  seconds away, never later. When the node does not answer, the job waits a
  minute; any other failure is retried a minute later. A node serving another
  chain ends the job with an error line, and the watch queues it again five
  minutes later (`Regents.Patchbay.Offers.Watch`).
  """

  use Oban.Worker,
    queue: :patchbay_offer_reads,
    max_attempts: 20,
    unique: [keys: [:chain_id, :market], period: :infinity, states: :incomplete]

  require Logger

  alias Regents.Patchbay.Offers
  alias Regents.Patchbay.Offers.{Client, Scanner}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"chain_id" => chain_id, "market" => market}}) do
    client = Client.configured()

    with true <- Offers.enabled?() and market == Offers.market(),
         {:ok, ^chain_id} <- client.chain_id(),
         result when result in [:ok, :moved] <- Scanner.pass(client, chain_id, market) do
      {:snooze, 300}
    else
      false ->
        {:cancel, :not_this_market}

      {:ok, other_chain} ->
        Logger.error(
          "Agent offers: the node serves chain #{other_chain}, not #{chain_id}; not reading it"
        )

        {:cancel, {:wrong_chain, other_chain}}

      {:error, :unavailable} ->
        Logger.warning("Agent offers: the node did not answer; reading again in a minute")
        {:snooze, 60}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl Oban.Worker
  def backoff(%Oban.Job{}), do: 60
end
