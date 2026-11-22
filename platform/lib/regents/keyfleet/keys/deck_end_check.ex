defmodule Regents.Keyfleet.Keys.DeckEndCheck do
  @moduledoc """
  Every hour (`config :regents, Oban, cron:`): saves with the site's errors
  (`Regents.Keyfleet.Keys.DeckEndingError`) each deployed fleet that has sold at least
  100 fewer Keys than its deck holds and no more than the deck, when it can
  sell Keys past its deck. Accelerant #1 is named from its 900th Key until its
  1,000th; its 1,001st is the first to draw its card with Chainlink
  randomness, so the Regents Safe readies the randomness subscription in that
  window (`docs/deployment.md`).

  It is one error naming every such fleet, saved again every hour while any
  fleet is in its window. A fleet whose supply is its deck, as Classic
  #1's and the Regents Club's are, never draws and is never named.
  """
  use Oban.Worker, queue: :keyfleet_default, max_attempts: 1

  alias Regents.Keyfleet.Fleets.{Presets, Rules}
  alias Regents.Keyfleet.Keys.DeckEndingError

  @warning 100

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    with [_ | _] = ending <- ending() do
      DeckEndingError.report(
        "Keys past the deck draw their card with Chainlink randomness soon: #{named(ending)}. " <>
          "Before the first of them sells, the Regents Safe adds the Key collection as a " <>
          "consumer of the randomness subscription and funds it in ETH (docs/deployment.md); " <>
          "until then those Keys wait in Revealing."
      )
    end

    :ok
  end

  defp ending do
    for fleet <- Regents.Keyfleet.Fleets.list_deployed_fleets!(),
        sells_past_deck?(fleet),
        {:ok, sold} = Regents.Keyfleet.Chain.minted(fleet.id),
        sold in (fleet.deck_size - @warning)..fleet.deck_size,
        do: {fleet, sold}
  end

  defp sells_past_deck?(fleet) do
    case Presets.max_supply(fleet.id) do
      nil -> true
      supply -> supply > fleet.deck_size
    end
  end

  defp named(ending),
    do:
      Enum.map_join(ending, ", ", fn {fleet, sold} ->
        "#{fleet.name} has sold #{Rules.grouped(sold)} of the #{Rules.grouped(fleet.deck_size)} " <>
          "Keys its deck deals"
      end)
end
