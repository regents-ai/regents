defmodule RegentsWeb.Keyfleet.Components.SeasonPicks do
  @moduledoc """
  One settled season's picks under its row on the fleet's record of seasons
  (`RegentsWeb.Keyfleet.SeasonsLive`), in the order they were locked, each with its
  Key, product, result and reason: a hundred as the row opens and a hundred
  more with each "More". The picks are a stream, so the page holds only where
  the next hundred start, and a list past two hundred lets go of its first
  ones as More adds more.

  Assigns: `id`, `fleet_id` and `number`, the season's, and `opened`, which
  the page gives anew each time the row opens. A row closed and opened again
  before the browser has let the list go keeps this component, so the list
  reads its first hundred again whenever `opened` changes, in place of any it
  sent, and reads nothing when the row is only drawn again.
  """
  use RegentsWeb, :live_component

  alias Regents.Keyfleet.Seasons
  alias RegentsWeb.Keyfleet.SeasonPanel

  # Picks the list opens with, and each "More" adds.
  @page 100

  # The picks a list keeps: the last two hundred it was given.
  @kept 200

  @impl true
  def mount(socket), do: {:ok, stream_configure(socket, :picks, dom_id: & &1.id)}

  @impl true
  def update(%{id: id, fleet_id: fleet_id, number: number, opened: opened}, socket) do
    socket = assign(socket, id: id, fleet_id: fleet_id, number: number, opened: opened)
    {:ok, if(changed?(socket, :opened), do: read(socket, nil, reset: true), else: socket)}
  end

  @impl true
  def handle_event("more", _params, %{assigns: %{more: place}} = socket) when is_integer(place),
    do: {:noreply, read(socket, place, [])}

  def handle_event("more", _params, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <ol id={"seasons-#{@number}-pick-list"} class="seasons-picks" phx-update="stream">
        <li :for={{dom_id, pick} <- @streams.picks} id={dom_id}>
          <span class="seasons-minor">Key {pick.key}</span>
          <span>{pick.product}</span>
          <span class="seasons-table__figure">{SeasonPanel.percent(pick.result)}</span>
          <q :if={pick.reason} class="seasons-picks__reason">{pick.reason}</q>
        </li>
      </ol>
      <Regent.Primitives.button
        :if={@more}
        id={"seasons-#{@number}-picks-more"}
        type="button"
        variant="secondary"
        arrow={false}
        phx-click="more"
        phx-target={@myself}
      >
        More
      </Regent.Primitives.button>
    </div>
    """
  end

  # The page of the season's picks after `place`, under those on show (or in
  # their place, with `reset: true`).
  defp read(%{assigns: %{fleet_id: fleet_id, number: number}} = socket, place, opts) do
    {picks, _more?} = page = Seasons.settled_picks_page(fleet_id, number, place, @page)

    socket
    |> assign(:more, Seasons.next_after(page))
    |> stream(:picks, Enum.map(picks, &pick(&1, number)), [limit: -@kept] ++ opts)
  end

  defp pick(pick, number),
    do: %{
      id: "seasons-#{number}-pick-#{pick.token_id}",
      key: pick.token_id,
      product: pick.product,
      result: pick.result,
      reason: pick.reason
    }
end
