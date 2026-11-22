defmodule RegentsWeb.Autolaunch.Components.AuctionStats do
  @moduledoc """
  The thin band of Revstake and Memestock auction counts shown on the
  auctions page (`Regents.Autolaunch.AuctionStats`). Each group loads on its
  own, so a slow or failed read leaves the other group's counts in place.
  """
  use Phoenix.Component

  alias Phoenix.LiveView.AsyncResult

  attr :revstake, AsyncResult, required: true
  attr :memestock, AsyncResult, required: true

  def auction_stats(assigns) do
    ~H"""
    <section id="auction-stats" class="auction-stats rg-support-band" aria-label="Auction counts">
      <.group id="auction-stats-revstake" title="Revstake Auctions" stats={@revstake} />
      <.group id="auction-stats-memestock" title="Memestock Auctions" stats={@memestock} />
    </section>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :stats, AsyncResult, required: true

  defp group(assigns) do
    ~H"""
    <div id={@id} class="auction-stats__group" aria-busy={to_string(@stats.loading != nil)}>
      <p class="auction-stats__title">{@title}</p>
      <p :if={@stats.failed} class="auction-stats__note">
        Counts unavailable right now
      </p>
      <dl :if={!@stats.failed} class="auction-stats__counts">
        <div>
          <dt>Live:</dt>
          <dd>{count(@stats, :live)}</dd>
        </div>
        <div>
          <dt>Graduated:</dt>
          <dd>{count(@stats, :graduated)}</dd>
        </div>
      </dl>
    </div>
    """
  end

  defp count(%{ok?: true, result: counts}, key), do: Map.fetch!(counts, key)
  defp count(_loading, _key), do: "…"
end
