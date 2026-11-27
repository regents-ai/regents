defmodule RegentsWeb.Keyfleet.SeasonsLive do
  @moduledoc """
  A fleet's record of settled seasons, at `/seasons` under the fleet's
  address, drawn inside the fleet's page under its bar
  (`RegentsWeb.Keyfleet.FleetLive`), for anyone: twenty at a time, newest first,
  with "More" for older ones, each with its holding, captain, the holding's
  result and how many Keys picked. Above them, "24h": what the holding came
  to over the last eight seasons settled, a day of them, or over as many as
  have settled (`Regents.Keyfleet.Seasons.Rules.compounded/1`). A season's row opens
  to its picks, a hundred at a time (`RegentsWeb.Keyfleet.Components.SeasonPicks`).

  The record is read as the page opens and as each "More" asks; a season
  settled meanwhile shows when the page is opened again. Its rows are a
  stream, two to a season (the season, then its picks, hidden until it is
  opened), so the page keeps only the newest and oldest numbers it has read
  and the season open; past a hundred seasons, the first ones leave the top
  as More adds more.
  """

  use RegentsWeb, :html

  import Phoenix.LiveView, only: [stream: 4, stream_insert: 4]

  alias Regents.Keyfleet.Fleets
  alias Regents.Keyfleet.Seasons
  alias Regents.Keyfleet.Seasons.Rules
  alias Regents.Keyfleet.Seasons.Season
  alias RegentsWeb.Keyfleet.Components.SeasonPicks
  alias RegentsWeb.Keyfleet.PageRead
  alias RegentsWeb.Keyfleet.SeasonPanel

  # How many settled seasons "24h" compounds: a day of three-hour seasons.
  @day 8

  # The seasons a page keeps: the last hundred it was given, two rows each.
  @kept_rows 2 * 100

  @doc "The address of the fleet's record of settled seasons."
  def seasons_path(fleet_id), do: "#{Fleets.path(fleet_id)}/seasons"

  @doc """
  The record named in the address, its newest page read for anyone, or
  nothing for any other page. A record that can't be read says so.
  """
  def read(socket, :seasons, %{"fleet_id" => fleet_id}) do
    case PageRead.run("seasons", fn -> Seasons.settled_page(fleet_id, nil) end) do
      {:ok, {seasons, more?}} ->
        day = Enum.take(seasons, @day)
        numbers = Enum.map(seasons, & &1.number)

        socket
        |> assign(:seasons, %{
          fleet_id: fleet_id,
          state: :read,
          newest: List.first(numbers),
          oldest: List.last(numbers),
          more?: more?,
          day: %{result: Rules.compounded(day), count: length(day)},
          open: nil
        })
        |> stream(:season_rows, rows(seasons), reset: true)

      {:error, _failure} ->
        assign(socket, :seasons, %{fleet_id: fleet_id, state: :unreadable})
    end
  end

  def read(socket, _route_id, _params), do: assign(socket, :seasons, nil)

  @doc """
  "More" adds the page of seasons settled before the oldest read, and a
  season's row opens to its picks, or closes when it is open.
  """
  def handle_event(
        "seasons_more",
        _params,
        %{assigns: %{seasons: %{state: :read, more?: true} = record}} = socket
      ) do
    {seasons, more?} = Seasons.settled_page(record.fleet_id, record.oldest)

    {:noreply,
     socket
     |> assign(:seasons, %{record | oldest: List.last(seasons).number, more?: more?})
     |> stream(:season_rows, rows(seasons), limit: -@kept_rows)}
  end

  def handle_event(
        "seasons_open",
        %{"number" => number},
        %{assigns: %{seasons: %{state: :read} = record}} = socket
      )
      when is_binary(number) do
    cond do
      record.open && Integer.to_string(record.open.number) == number ->
        {:noreply, opened(socket, record, nil)}

      row = shown(record, number) ->
        {:noreply, opened(socket, record, row)}

      true ->
        {:noreply, socket}
    end
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  attr :seasons, :map, required: true, doc: "the record as `read/3` reads it"
  attr :rows, :any, required: true, doc: "the record's rows, as a stream"

  @doc "The record page."
  def page(assigns) do
    ~H"""
    <article id="seasons-page" class="seasons-page">
      <section class="seasons-panel" aria-labelledby="seasons-title">
        <p class="seasons-kicker">
          <.link patch={Fleets.path(@seasons.fleet_id)}>
            ← {Fleets.name(@seasons.fleet_id)}
          </.link>
        </p>
        <h2 id="seasons-title">
          Seasons
          <Regent.Primitives.tip id="seasons-title-tip" label="About Seasons record">
            Settled three-hour rounds. Click any season row to inspect individual Key picks.
          </Regent.Primitives.tip>
        </h2>

        <Regent.Primitives.empty_state
          :if={@seasons.state == :unreadable}
          id="seasons-unreadable"
          class="kf-empty"
          title="The seasons couldn’t be loaded. Refresh the page to try again."
        />

        <Regent.Primitives.empty_state
          :if={@seasons.state == :read and is_nil(@seasons.newest)}
          id="seasons-empty"
          class="kf-empty"
          title="No season has ended yet."
        />

        <dl :if={@seasons.state == :read and @seasons.newest} class="seasons-day">
          <div>
            <dt>24h</dt>
            <dd id="seasons-day">
              <span class="seasons-day__figure">{SeasonPanel.percent(@seasons.day.result)}</span>
              <span class="seasons-minor">{seasons_counted(@seasons.day.count)}</span>
            </dd>
          </div>
        </dl>

        <div
          :if={@seasons.state == :read and @seasons.newest}
          class="seasons-table-frame"
          role="region"
          tabindex="0"
          aria-labelledby="seasons-title"
        >
          <table id="seasons-table" class="seasons-table">
            <thead>
              <tr>
                <th scope="col">Season</th>
                <th scope="col">Holding</th>
                <th scope="col">Captain</th>
                <th scope="col" class="seasons-table__figure">Result</th>
                <th scope="col" class="seasons-table__figure">Picks</th>
              </tr>
            </thead>
            <tbody id="seasons-rows" phx-update="stream">
              <tr
                :for={{dom_id, item} <- @rows}
                id={dom_id}
                hidden={item.kind == :picks and is_nil(item.opened)}
              >
                <.season :if={item.kind == :season} row={item.row} open?={not is_nil(item.opened)} />
                <td :if={item.kind == :picks and item.opened} colspan="5">
                  <p :if={item.row.pick_count == 0} class="fleet-detail">
                    No Key picked this season.
                  </p>
                  <.live_component
                    :if={item.row.pick_count > 0}
                    module={SeasonPicks}
                    id={"seasons-#{item.row.number}-pick-list"}
                    fleet_id={@seasons.fleet_id}
                    number={item.row.number}
                    opened={item.opened}
                  />
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <Regent.Primitives.button
          :if={@seasons.state == :read and @seasons.more?}
          id="seasons-more"
          type="button"
          variant="secondary"
          arrow={false}
          phx-click="seasons_more"
        >
          More
        </Regent.Primitives.button>

        <SeasonPanel.terms />
      </section>
    </article>
    """
  end

  attr :row, :map, required: true
  attr :open?, :boolean, required: true

  # A settled season's cells; its number opens its picks in the row under it.
  defp season(assigns) do
    ~H"""
    <th scope="row">
      <button
        type="button"
        class="seasons-table__open"
        phx-click="seasons_open"
        phx-value-number={@row.number}
        aria-expanded={to_string(@open?)}
        aria-controls={"seasons-#{@row.number}-picks"}
      >
        <span>Season {@row.number}</span>
        <RegentsWeb.Keyfleet.Time.local
          id={"seasons-#{@row.number}-at"}
          at={@row.starts_at}
          as={:stamp}
          class="seasons-minor"
        />
      </button>
    </th>
    <td>
      <span :if={@row.pick_count == 0 and @row.holding == "USDC"} class="seasons-minor">
        Idle (USDC)
      </span>
      <span :if={@row.pick_count > 0 or @row.holding != "USDC"}>{@row.holding}</span>
    </td>
    <td>{SeasonPanel.captain(@row.captain_key)}</td>
    <td class="seasons-table__figure">{SeasonPanel.percent(@row.result)}</td>
    <td class="seasons-table__figure">{@row.pick_count}</td>
    """
  end

  defp seasons_counted(1), do: "1 season"
  defp seasons_counted(count), do: "#{count} seasons"

  # Closes the season open, if any, and opens `row`, if given, each where it
  # stands on the page; a season the page has let go of stays gone. Each
  # opening is numbered anew, so the season's picks read their first hundred
  # again even when its list is still the one drawn before.
  defp opened(socket, record, row) do
    socket
    |> update_rows(record.open, nil)
    |> update_rows(row, System.unique_integer([:positive, :monotonic]))
    |> assign(:seasons, %{record | open: row})
  end

  defp update_rows(socket, nil, _opened), do: socket

  defp update_rows(socket, row, opened),
    do:
      Enum.reduce(
        items(row, opened),
        socket,
        &stream_insert(&2, :season_rows, &1, update_only: true)
      )

  # The season numbered `number` among those the page has read, read again,
  # since the page keeps none of them.
  defp shown(%{newest: nil}, _number), do: nil

  defp shown(record, number) do
    with {number, ""} <- Integer.parse(number),
         true <- number in record.oldest..record.newest//1,
         %Season{} = season <- Seasons.settled_season(record.fleet_id, number) do
      row(season)
    else
      _not_shown -> nil
    end
  end

  defp rows(seasons), do: Enum.flat_map(seasons, &items(row(&1), nil))

  # A season's two rows: its own, and its picks' under it; `opened` is nil
  # while the season is closed, and the number of its opening while open.
  defp items(row, opened),
    do: [
      %{id: "seasons-#{row.number}", kind: :season, row: row, opened: opened},
      %{id: "seasons-#{row.number}-picks", kind: :picks, row: row, opened: opened}
    ]

  defp row(season),
    do: %{
      number: season.number,
      starts_at: season.starts_at,
      holding: season.holding,
      captain_key: season.captain_key,
      result: season.holding_result,
      pick_count: season.keys_locked
    }
end
