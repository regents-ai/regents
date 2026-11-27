defmodule RegentsWeb.Keyfleet.SeasonPanel do
  @moduledoc """
  The hall's "Season" panel (`Regents.Keyfleet.Seasons`): what the fleet holds this
  season and its open price, its captain, the time the season has left, and
  how the season settled last went for the holding and whether its crown
  passed. A member also reads the season under way's picks, ten at a time,
  the last hundred kept, through the page's `:season_picks` stream, and a Key
  holder locks or changes their Key's pick for the season taking picks,
  through the same `Regents.Keyfleet.Seasons.pick/4` an agent's goes through.
  Before its season starts a pick is its Key's own: the panel reads the
  reader's pick and how many Keys have locked one, never another Key's pick.

  Anyone reads the season under way and the settled ones. A reader who isn't
  a member sees the panel drawn from the fleet's reading every such page
  shares (`RegentsWeb.Keyfleet.FleetNow`, which holds `face/1`), so a crowd of them
  costs what one visitor costs. A member's page reads its own and hears the
  fleet's turns on `Regents.Keyfleet.Seasons.topic/1`, which read the panel again,
  and the picks locked for the season taking picks on `season_topic/1`, which
  read only that season's count and the reader's own pick. The clock counts
  down in the browser (`RegentsWeb.Keyfleet.Components.Countdown`), and from the
  season's end says "Settling" until the turn's notice draws the next; nothing
  here keeps time.

  The fleet's record of settled seasons is its own page
  (`RegentsWeb.Keyfleet.SeasonsLive`).
  """

  use RegentsWeb, :html

  import RegentsWeb.Keyfleet.Components.Countdown
  import Phoenix.LiveView, only: [connected?: 1, stream: 4]

  alias Phoenix.Socket.Broadcast
  alias Regents.Keyfleet.Seasons
  alias Regents.Keyfleet.Seasons.CoinList
  alias Regents.Keyfleet.Seasons.Errors
  alias Regents.Keyfleet.Seasons.Validations.Reason
  alias RegentsWeb.Keyfleet.BoxLimit
  alias RegentsWeb.Keyfleet.SeasonsLive
  alias RegentsWeb.Keyfleet.ShellLive

  # Picks of the season under way a page shows at first, and each "More" adds;
  # and the most it keeps, the earliest let go, as many as a page of the
  # record holds.
  @picks 10
  @kept_picks 100

  @coinbase "https://docs.cdp.coinbase.com/ai-agents/coinbase-for-agents/coinbase-mcp"

  @notes %{
    locked: "Locked.",
    closed: "Season closed. Pick again for the next one.",
    not_open: "That product isn’t open to picks now.",
    unread: "The list of products isn’t read yet. Try again in a few minutes.",
    no_key: "Only a Key holder picks."
  }

  @doc """
  The season under way as anyone reads it, or nil while none is: its number,
  when it ends, its holding and that holding's open price, its captain, and
  `last`, the season settled as it started, with the holding's result over
  it and whether the crown passed (the holding changed).
  """
  def face(fleet_id) do
    case Seasons.running_season!(fleet_id) do
      nil ->
        nil

      running ->
        last = Seasons.last_settled(fleet_id, running.number)

        %{
          number: running.number,
          ends_at: running.ends_at,
          holding: running.holding,
          open_price: running.holding_open_price,
          captain_key: running.captain_key,
          last:
            last &&
              %{
                number: last.number,
                result: last.holding_result,
                passed?: running.holding != last.holding
              }
        }
    end
  end

  @doc """
  The panel for the hall of `fleet_id` on show, in `:season`: drawn from the
  fleet's reading (`reading`) for a reader who isn't a member, or read for a
  member, who then hears the fleet's seasons. A member's panel already on
  show is kept as it is. Any other view shows none.
  """
  def show(socket, fleet_id, :hall, %{season: face}) do
    socket
    |> listen([])
    |> assign(:season, %{fleet_id: fleet_id, member?: false, now: now(), face: face, taking: nil})
  end

  def show(socket, fleet_id, :hall, nil) do
    cond do
      not ShellLive.member?(socket, fleet_id) -> leave(socket)
      match?(%{fleet_id: ^fleet_id, member?: true}, socket.assigns.season) -> socket
      true -> read(socket, fleet_id)
    end
  end

  def show(socket, _fleet_id, _view, _reading), do: leave(socket)

  @doc "No panel, and nothing of the seasons heard."
  def leave(socket), do: socket |> listen([]) |> assign(:season, nil)

  attr :season, :map, required: true, doc: "the panel as `show/4` gives it"
  attr :picks, :any, required: true, doc: "the page's `:season_picks` stream"

  @doc "The panel, while there is a season to show."
  def panel(assigns) do
    ~H"""
    <section
      :if={@season.face || @season.taking}
      id="fleet-season"
      class="fleet-season"
      aria-labelledby="fleet-season-title"
    >
      <h2 id="fleet-season-title">
        Season
        <Regent.Primitives.tip id="fleet-season-tip" label="About Seasons">
          Three-hour asset-picking rounds. Keys pick a Coinbase asset; the fleet tracks the winning pick.
        </Regent.Primitives.tip>
      </h2>
      <dl class="fleet-season__facts">
        <div>
          <dt>
            <Regent.Primitives.tip id="fleet-season-holding-tip">
              <:figure>Holding</:figure>
              Asset tracked by the fleet this round, and its opening price.
            </Regent.Primitives.tip>
          </dt>
          <dd id="fleet-season-holding">
            <span :if={@season.face}>{@season.face.holding}</span>
            <span :if={@season.face} class="fleet-season__minor">
              {price(@season.face.open_price)}
            </span>
            <span :if={is_nil(@season.face)}>—</span>
          </dd>
        </div>
        <div>
          <dt>
            <Regent.Primitives.tip id="fleet-season-captain-tip">
              <:figure>Captain</:figure>
              Key whose pick won the previous round.
            </Regent.Primitives.tip>
          </dt>
          <dd id="fleet-season-captain">{captain(@season.face && @season.face.captain_key)}</dd>
        </div>
        <div>
          <dt>Clock</dt>
          <dd>
            <.countdown
              :if={@season.face}
              id="fleet-season-clock"
              closes_at={@season.face.ends_at}
              now={@season.now}
              format="hours"
              done="Settling"
            />
            <span :if={is_nil(@season.face)}>—</span>
          </dd>
        </div>
        <div>
          <dt>
            <Regent.Primitives.tip id="fleet-season-last-tip">
              <:figure>Last</:figure>
              Previous round return. Crown kept, passed, or dropped tracks leadership.
            </Regent.Primitives.tip>
          </dt>
          <dd id="fleet-season-last">
            <span :if={is_nil(@season.face && @season.face.last)}>—</span>
            <span :if={@season.face && @season.face.last}>
              <span class="fleet-season__figure">{percent(@season.face.last.result)}</span>
              <span class="fleet-season__minor">
                {crown(@season.face)}
              </span>
            </span>
          </dd>
        </div>
      </dl>

      <.pick :if={@season.member? and @season.taking} season={@season} />
      <.picks :if={@season.member? and @season.face} season={@season} picks={@picks} />

      <.terms />
      <.link id="fleet-season-record" patch={SeasonsLive.seasons_path(@season.fleet_id)}>
        Record
      </.link>
    </section>
    """
  end

  @doc "The line under the panel and the record: what the results are, and what Keyfleet does not do."
  def terms(assigns) do
    ~H"""
    <p class="fleet-detail fleet-season__terms">
      Results are records, not forecasts. Keyfleet places no order and holds no money. To follow,
      your agent trades in your own <a href={coinbase()} rel="noopener" target="_blank">Coinbase</a>
      account.
    </p>
    """
  end

  attr :season, :map, required: true

  # The reader's Key's pick for the season taking picks, and the form that
  # locks or changes it.
  defp pick(assigns) do
    ~H"""
    <div id="fleet-season-pick" class="fleet-season__pick">
      <h3>Pick</h3>
      <p class="fleet-detail" id="fleet-season-taking">
        Season {@season.taking.number} · {locked(@season.taking.count)}
      </p>
      <p :if={@season.taking.mine} id="fleet-season-mine" class="fleet-season__mine">
        <span>Your pick</span>
        <strong>{@season.taking.mine.product}</strong>
        <q :if={@season.taking.mine.reason}>{@season.taking.mine.reason}</q>
      </p>
      <.form
        for={@season.form}
        id="fleet-season-form"
        class="fleet-season__form"
        phx-change="season_pick"
        phx-submit="season_lock"
      >
        <Regent.Primitives.field :let={field} id="fleet-season-product" label="Product">
          <select
            id={field.id}
            name={@season.form[:product].name}
            aria-describedby={field.described_by}
            required
          >
            <option
              :for={product <- @season.coins}
              value={product}
              selected={product == @season.form[:product].value}
            >
              {product}
            </option>
          </select>
        </Regent.Primitives.field>
        <Regent.Primitives.field :let={field} id="fleet-season-reason" label="Reason (optional)">
          <textarea
            id={field.id}
            name={@season.form[:reason].name}
            rows="2"
            maxlength={BoxLimit.maxlength(longest_reason())}
            aria-describedby={field.described_by}
          >{Phoenix.HTML.Form.normalize_value("textarea", @season.form[:reason].value)}</textarea>
        </Regent.Primitives.field>
        <div class="fleet-season__lock">
          <Regent.Primitives.button type="submit" arrow={false}>Lock</Regent.Primitives.button>
          <p
            id="fleet-season-note"
            class="fleet-season__note"
            role="status"
            phx-hook="MotionRefusal"
            data-refused={@season.note not in [nil, :locked]}
          >
            {@season.note && note(@season.note)}
          </p>
        </div>
        <p :if={@season.taking.mine} class="fleet-detail">
          Changing your pick gives up its place.
        </p>
      </.form>
    </div>
    """
  end

  attr :season, :map, required: true
  attr :picks, :any, required: true

  # The season under way's picks, in the order they were locked, a page at a
  # time.
  defp picks(assigns) do
    ~H"""
    <div id="fleet-season-picks" class="fleet-season__picks">
      <h3>Picks</h3>
      <p :if={@season.no_picks?} class="fleet-detail">No picks this season.</p>
      <ol
        :if={not @season.no_picks?}
        id="fleet-season-pick-list"
        class="fleet-season__list"
        phx-update="stream"
      >
        <li :for={{dom_id, pick} <- @picks} id={dom_id}>
          <span class="fleet-season__key">Key {pick.key}</span>
          <span>{pick.product}</span>
          <span class="fleet-season__figure">{price(pick.open_price)}</span>
          <q :if={pick.reason} class="fleet-season__reason">{pick.reason}</q>
        </li>
      </ol>
      <Regent.Primitives.button
        :if={@season.more}
        id="fleet-season-more"
        variant="secondary"
        arrow={false}
        phx-click="season_more"
      >
        More
      </Regent.Primitives.button>
    </div>
    """
  end

  @doc "What the panel's form and \"More\" do."
  def handle_event("season_pick", %{"pick" => params}, %{assigns: %{season: %{form: _}}} = socket)
      when is_map(params),
      do: {:noreply, update(socket, :season, &%{&1 | form: pick_form(params), note: nil})}

  def handle_event(
        "season_lock",
        %{"pick" => params},
        %{assigns: %{season: %{taking: %{number: number}} = season}} = socket
      )
      when is_map(params) do
    typed = Map.take(params, ["product", "reason"])

    if BoxLimit.too_long?(to_string(typed["reason"]), longest_reason()) do
      note = Errors.ReasonError.exception(rule: :too_long)
      {:noreply, assign(socket, :season, %{season | form: pick_form(typed), note: note})}
    else
      actor = ShellLive.human_actor(socket)

      case Seasons.pick(season.fleet_id, number, typed, actor: actor) do
        {:ok, _pick} ->
          {:noreply, socket |> reread_taking() |> update(:season, &%{&1 | note: :locked})}

        {:error, error} ->
          {:noreply,
           assign(socket, :season, %{season | form: pick_form(typed), note: refused(error)})}
      end
    end
  end

  def handle_event(
        "season_more",
        _params,
        %{assigns: %{season: %{more: place} = season}} = socket
      )
      when is_integer(place) do
    {:ok, {picks, _more?} = page} =
      Seasons.picks_page(
        season.fleet_id,
        season.face.number,
        place,
        @picks,
        ShellLive.reads_as(socket, season.fleet_id)
      )

    {:noreply,
     socket
     |> assign(:season, %{season | more: Seasons.next_after(page)})
     |> show_picks(picks, [])}
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @doc """
  A turn of the fleet whose panel a member's page shows reads the panel
  again; a pick locked for its season taking picks reads that season's count
  and the reader's own pick, and leaves what they are typing.
  """
  def heard(%{assigns: %{season: %{member?: true, fleet_id: fleet_id}}} = socket, %Broadcast{
        event: "seasons_changed",
        topic: topic
      }) do
    if topic == Seasons.topic(fleet_id), do: read(socket, fleet_id), else: socket
  end

  def heard(%{assigns: %{season: %{member?: true, taking: %{id: id}}}} = socket, %Broadcast{
        event: "season_changed",
        topic: topic
      }) do
    if topic == Seasons.season_topic(id), do: reread_taking(socket), else: socket
  end

  def heard(socket, _notice), do: socket

  @doc "The holding's or a pick's price as Coinbase sent it, in US dollars, or a dash for none."
  def price(nil), do: "—"

  def price(%Decimal{} = price) do
    case price |> Decimal.to_string(:normal) |> String.split(".") do
      [whole] -> "$" <> RegentFormat.add_delimiters(whole)
      [whole, cents] -> "$" <> RegentFormat.add_delimiters(whole) <> "." <> cents
    end
  end

  @doc "A result over a season as a signed percentage to two places, or a dash for none."
  def percent(nil), do: "—"

  def percent(%Decimal{} = result) do
    shown = result |> Decimal.mult(100) |> Decimal.round(2)

    cond do
      Decimal.eq?(shown, 0) -> "0.00%"
      Decimal.positive?(shown) -> "+" <> Decimal.to_string(shown, :normal) <> "%"
      true -> "−" <> (shown |> Decimal.abs() |> Decimal.to_string(:normal)) <> "%"
    end
  end

  @doc "A captain's Key, or a dash for none."
  def captain(nil), do: "—"
  def captain(key), do: "Key #{key}"

  # What became of the crown as the last season settled: kept by its holding,
  # passed to a pick's Key, or let go to USDC with no Key taking it.
  defp crown(%{last: %{passed?: false}}), do: "Crown kept"
  defp crown(%{captain_key: nil}), do: "Crown dropped"
  defp crown(_face), do: "Crown passed"

  defp coinbase, do: @coinbase

  # The longest reason the rule takes, in the UTF-16 units a box counts
  # (`RegentsWeb.Keyfleet.BoxLimit`), as the rule counts it. More, as typed, is refused
  # before the rule is asked; the rule may refuse more. Asked as the page
  # runs, so the panel doesn't compile with the rule.
  defp longest_reason, do: Reason.longest()

  # A member's panel: what anyone reads, the season under way's first picks,
  # and the season taking picks with how many Keys locked one and the
  # reader's own; the page then hears the fleet's turns and that season.
  defp read(socket, fleet_id) do
    opts = ShellLive.reads_as(socket, fleet_id)
    face = face(fleet_id)

    {picks, more} =
      case face do
        nil ->
          {[], nil}

        %{number: number} ->
          {:ok, {picks, _more?} = page} = Seasons.picks_page(fleet_id, number, nil, @picks, opts)
          {picks, Seasons.next_after(page)}
      end

    taking = taking(fleet_id, opts)

    socket
    |> assign(:season, %{
      fleet_id: fleet_id,
      member?: true,
      now: now(),
      face: face,
      no_picks?: picks == [],
      more: more,
      taking: taking,
      coins: coins(),
      form: pick_form(taking && taking.mine),
      note: nil
    })
    |> show_picks(picks, reset: true)
    |> listen(topics(fleet_id, taking))
  end

  # The season under way's picks to the page's stream, after those it shows
  # (or in their place, with `reset: true`), the last hundred kept.
  defp show_picks(socket, picks, opts),
    do:
      stream(
        socket,
        :season_picks,
        Enum.map(picks, &shown_pick/1),
        [limit: -@kept_picks] ++ opts
      )

  defp reread_taking(%{assigns: %{season: %{fleet_id: fleet_id} = season}} = socket) do
    taking = taking(fleet_id, ShellLive.reads_as(socket, fleet_id))

    socket
    |> assign(:season, %{season | taking: taking})
    |> listen(topics(fleet_id, taking))
  end

  # The season taking picks, while it takes them, with how many Keys locked a
  # pick for it and the reader's own Key's pick.
  defp taking(fleet_id, opts) do
    with %{} = season <- Seasons.upcoming_season!(fleet_id, opts),
         true <- Seasons.taking_picks?(season) do
      mine = Seasons.my_pick!(fleet_id, season.number, opts)

      %{
        id: season.id,
        number: season.number,
        count: season.keys_locked,
        mine: mine && %{product: mine.product, reason: mine.reason}
      }
    else
      _none -> nil
    end
  end

  defp topics(fleet_id, nil), do: [Seasons.topic(fleet_id)]
  defp topics(fleet_id, %{id: id}), do: [Seasons.topic(fleet_id), Seasons.season_topic(id)]

  defp listen(socket, topics) do
    heard = Map.get(socket.assigns, :season_topics, [])

    if connected?(socket) and topics != heard do
      Enum.each(heard -- topics, &Phoenix.PubSub.unsubscribe(Regents.PubSub, &1))
      Enum.each(topics -- heard, &Phoenix.PubSub.subscribe(Regents.PubSub, &1))
      assign(socket, :season_topics, topics)
    else
      socket
    end
  end

  # The products a pick may name, USDC first and the rest by name; none while
  # the list isn't read, and every pick is refused as not checked.
  defp coins do
    case CoinList.listing() do
      {:ok, products, _read_at} ->
        {usdc, listed} = Enum.split_with(products, &(&1 == "USDC"))
        usdc ++ Enum.sort(listed)

      {:error, :unavailable} ->
        []
    end
  end

  defp pick_form(%{product: product, reason: reason}),
    do: pick_form(%{"product" => product, "reason" => reason})

  defp pick_form(params) when is_map(params), do: to_form(params, as: :pick)
  defp pick_form(nil), do: to_form(%{}, as: :pick)

  defp shown_pick(pick),
    do: %{
      key: pick.token_id,
      product: pick.product,
      open_price: pick.open_price,
      reason: pick.reason
    }

  defp refused(%Ash.Error.Framework{errors: [%Errors.ProductsUnreadError{}]}), do: :unread
  defp refused(%Ash.Error.Forbidden{}), do: :no_key

  defp refused(%Ash.Error.Invalid{errors: errors}) do
    cond do
      Enum.any?(
        errors,
        &(is_struct(&1, Errors.PicksClosedError) or is_struct(&1, Errors.SeasonUnknownError))
      ) ->
        :closed

      reason = Enum.find(errors, &is_struct(&1, Errors.ReasonError)) ->
        reason

      true ->
        :not_open
    end
  end

  # A reason's refusal says the rule it broke, as an agent's does.
  defp note(%Errors.ReasonError{} = reason), do: Exception.message(reason)
  defp note(note), do: Map.fetch!(@notes, note)

  defp locked(1), do: "1 Key locked"
  defp locked(count), do: "#{count} Keys locked"

  defp now, do: DateTime.utc_now()
end
