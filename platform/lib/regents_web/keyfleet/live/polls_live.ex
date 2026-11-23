defmodule RegentsWeb.Keyfleet.PollsLive do
  @moduledoc """
  A fleet's polls, for the people holding its Keys, or a shard of one: the
  active ones newest first, then the past ones, and each poll's own page
  with its choices, the starter's notes and, once it closes, each choice's
  count of votes and what each Key voted and why. Anyone else is told the
  polls are for the fleet's Keys and is shown none of them
  (`Regents.Keyfleet.Access`, `:polls`).

  Holders start polls (one a day for each Key) and vote; a poll's starter
  can end it early. Each press goes through the same `Regents.Keyfleet.Polls` action
  an agent's request does, as the person signed in, and is turned down for
  the same reasons (`RegentsWeb.Keyfleet.PollRefusal`).

  The page reads what it shows as the reader, and reads it again when it
  changes: a poll started or ended, a vote, a poll closing, a press of the
  reader's own, and Keys changing hands.

  The countdown is drawn in the browser. The server keeps no clock running:
  a page's one timer waits for the close itself.
  """

  use RegentsWeb, :html

  import Regents.Keyfleet.Fleets.Rules, only: [counted: 3]
  import RegentsWeb.Keyfleet.Components.Countdown
  import RegentsWeb.Keyfleet.Components.Footnote
  import RegentsWeb.Keyfleet.Components.LoadFailed
  import Phoenix.LiveView, only: [connected?: 1, push_patch: 2]

  alias Phoenix.Socket.Broadcast
  alias Regents.Keyfleet.Chain
  alias Regents.Keyfleet.Fleets
  alias Regents.Keyfleet.Fleets.Rules
  alias Regents.Keyfleet.Polls
  alias Regents.Keyfleet.Polls.Poll
  alias RegentsWeb.Keyfleet.ActivityLines
  alias RegentsWeb.Keyfleet.BoxLimit
  alias RegentsWeb.Keyfleet.Components.Count
  alias RegentsWeb.Keyfleet.KeyLinks
  alias RegentsWeb.Keyfleet.KeysLive
  alias RegentsWeb.Keyfleet.PageRead
  alias RegentsWeb.Keyfleet.PollRefusal
  alias RegentsWeb.Keyfleet.ShellLive
  alias RegentsWeb.Keyfleet.WorkspacePage

  @lengths [1, 5, 10, 15, 30, 45, 60]
  # A poll page that couldn't be read again looks again after this long.
  @look_again_ms 5_000
  # The longest choices a poll's rule takes, in the UTF-16 units a box
  # counts (`RegentsWeb.Keyfleet.BoxLimit`): ten of 100 letters, each letter an
  # emoji of two units, one per line. More, as typed, is refused as too long
  # before the rule is asked, and the rule may refuse more.
  @longest_choices 10 * 100 * 2 + 9

  attr :page, :any, required: true, doc: "the polls as read, or `:unreadable`"
  attr :form, Phoenix.HTML.Form, default: nil, doc: "the form starting a poll"
  attr :notice, :map, default: nil

  def list(%{page: :unreadable} = assigns), do: ~H|<.unreadable id="polls-page" />|
  def list(%{page: %{fleet_name: nil}} = assigns), do: ~H|<.missing_fleet id="polls-page" />|
  def list(%{page: %{kind: :locked}} = assigns), do: ~H|<.locked id="polls-page" page={@page} />|

  def list(assigns) do
    {active, past} = Enum.split_with(assigns.page.polls, & &1.open?)
    assigns = assign(assigns, active: active, past: past)

    ~H"""
    <article id="polls-page" class="polls-page">
      <header class="polls-heading">
        <p class="polls-kicker">
          <.link patch={Regents.Keyfleet.Fleets.path(@page.fleet_id)}>{@page.fleet_name}</.link>
        </p>
        <h1 tabindex="-1">Polls</h1>
        <p class="polls-lede">Questions this fleet’s Keys answer together.</p>
      </header>

      <.notice notice={@notice} />

      <section
        :if={@page.voter}
        id="polls-start"
        class="polls-panel"
        aria-labelledby="polls-start-title"
      >
        <h2 id="polls-start-title">
          New poll
          <Regent.Primitives.tip id="polls-start-tip" label="About starting a poll">
            You ask as Key {Rules.grouped(@page.voter.key)}. A poll asks one question and stays open from 1 minute to an hour; you can end it early. Each Key starts one poll a day.
          </Regent.Primitives.tip>
        </h2>

        <p :if={@page.last_started} id="polls-start-limit" class="polls-detail">
          Key {Rules.grouped(@page.voter.key)} started a poll in the last day. It can start another after
          <RegentsWeb.Keyfleet.Time.local
            id="polls-start-after"
            at={DateTime.add(@page.last_started.inserted_at, 1, :day)}
            as={:stamp}
          />.
        </p>

        <.form
          :if={is_nil(@page.last_started)}
          for={@form}
          id="polls-start-form"
          class="polls-form"
          phx-submit="start_poll"
        >
          <Regent.Primitives.field
            :let={field}
            id="polls-start-question"
            class="polls-field"
            label="Question"
            errors={errors(@form[:question], "Ask in up to 200 characters, on one line.")}
          >
            <input
              id={field.id}
              name={@form[:question].name}
              value={Map.get(@form.params, "question", "")}
              maxlength="200"
              required
              autocomplete="off"
              aria-invalid={field.aria_invalid}
              aria-describedby={field.described_by != "" && field.described_by}
            />
          </Regent.Primitives.field>

          <Regent.Primitives.field
            :let={field}
            id="polls-start-choices"
            class="polls-field"
            label="Choices, one per line"
            errors={
              errors(@form[:choices], "Give 2 to 10 different choices, each up to 100 characters.")
            }
          >
            <textarea
              id={field.id}
              name={@form[:choices].name}
              rows="4"
              maxlength={choices_box()}
              required
              aria-invalid={field.aria_invalid}
              aria-describedby={field.described_by != "" && field.described_by}
            >{Phoenix.HTML.Form.normalize_value("textarea", @form.params["choices"])}</textarea>
          </Regent.Primitives.field>

          <Regent.Primitives.field
            :let={field}
            id="polls-start-notes"
            class="polls-field"
            label="Notes (optional)"
            errors={errors(@form[:notes], "Keep notes to 2,000 characters.")}
          >
            <:hint>Only this fleet’s Key holders see them.</:hint>
            <textarea
              id={field.id}
              name={@form[:notes].name}
              rows="3"
              maxlength="2000"
              aria-invalid={field.aria_invalid}
              aria-describedby={field.described_by != "" && field.described_by}
            >{Phoenix.HTML.Form.normalize_value("textarea", @form.params["notes"])}</textarea>
          </Regent.Primitives.field>

          <Regent.Primitives.field
            :let={field}
            id="polls-start-minutes"
            class="polls-field"
            label="Open for"
          >
            <select id={field.id} name={@form[:minutes].name}>
              <option
                :for={minutes <- lengths()}
                value={minutes}
                selected={Map.get(@form.params, "minutes", "30") == to_string(minutes)}
              >
                {length_label(minutes)}
              </option>
            </select>
          </Regent.Primitives.field>

          <div class="sticky-actions">
            <Regent.Primitives.button type="submit">Start poll</Regent.Primitives.button>
          </div>
        </.form>
      </section>

      <section id="polls-active" class="polls-panel" aria-labelledby="polls-active-title">
        <h2 id="polls-active-title">Active</h2>
        <Regent.Primitives.empty_state
          :if={@active == [] and can_ask?(@page)}
          id="polls-active-empty"
          class="kf-empty"
          title="No active polls."
        >
          Ask the fleet a question above.
        </Regent.Primitives.empty_state>
        <Regent.Primitives.empty_state
          :if={@active == [] and not can_ask?(@page)}
          id="polls-active-empty"
          class="kf-empty"
          title="No active polls."
        />
        <ol :if={@active != []} class="polls-list">
          <.list_item :for={poll <- @active} poll={poll} page={@page} active />
        </ol>
      </section>

      <section id="polls-past" class="polls-panel" aria-labelledby="polls-past-title">
        <h2 id="polls-past-title">Past</h2>
        <Regent.Primitives.empty_state
          :if={@past == []}
          id="polls-past-empty"
          class="kf-empty"
          title="No past polls yet."
        />
        <ol :if={@past != []} class="polls-list">
          <.list_item :for={poll <- @past} poll={poll} page={@page} active={false} />
        </ol>
      </section>
    </article>
    """
  end

  attr :poll, :map, required: true
  attr :page, :map, required: true
  attr :active, :boolean, required: true

  defp list_item(assigns) do
    ~H"""
    <li id={"poll-#{@poll.id}"} class="polls-card" data-poll={@poll.id}>
      <h3>
        <.link patch={poll_path(@page.fleet_id, @poll.id)}>{@poll.question}</.link>
      </h3>
      <p class="polls-detail">
        Started by {ActivityLines.key_name(@poll.started_by_key, @poll.agent)} ·
        <span>{counted(@poll.votes_cast, "vote", "votes")}</span>
      </p>
      <p class="polls-detail">
        <.countdown
          :if={@active}
          id={"poll-left-#{@poll.id}"}
          closes_at={@poll.closes_at}
          now={@page.now}
          format="minutes"
        />
        <span :if={!@active}>
          {result(@poll.totals)} · Closed
          <RegentsWeb.Keyfleet.Time.local
            id={"poll-closed-#{@poll.id}"}
            at={Polls.closed_at(@poll)}
            as={:stamp}
          />
        </span>
      </p>
    </li>
    """
  end

  attr :page, :any, required: true, doc: "the poll as read, or `:unreadable`"
  attr :notice, :map, default: nil

  def detail(%{page: :unreadable} = assigns), do: ~H|<.unreadable id="poll-page" />|
  def detail(%{page: %{fleet_name: nil}} = assigns), do: ~H|<.missing_fleet id="poll-page" />|
  def detail(%{page: %{kind: :locked}} = assigns), do: ~H|<.locked id="poll-page" page={@page} />|

  def detail(%{page: %{poll: nil}} = assigns) do
    ~H"""
    <article id="poll-page" class="polls-page">
      <.detail_heading page={@page} title="Polls" />
      <section id="poll-missing" class="polls-panel">
        <h2>This fleet has no such poll.</h2>
        <.link patch={list_path(@page.fleet_id)}>See every poll</.link>
      </section>
    </article>
    """
  end

  def detail(assigns) do
    poll = assigns.page.poll
    voter = assigns.page.voter
    open? = poll.open?

    assigns =
      assign(assigns,
        poll: poll,
        open?: open?,
        can_vote?: open? and voter != nil and is_nil(assigns.page.my_vote),
        starter?: voter != nil and voter.key == poll.started_by_key
      )

    ~H"""
    <article id="poll-page" class="polls-page">
      <.detail_heading page={@page} title={@poll.question} />

      <p id="poll-status" class="polls-status">
        <span class="polls-badge" data-open={to_string(@open?)}>
          {if @open?, do: "Active", else: "Closed"}
        </span>
        Started by
        <.link patch={KeyLinks.key_path(@page.fleet_id, @poll.started_by_key)}>
          {ActivityLines.key_name(@poll.started_by_key, @poll.agent)}
        </.link>
        ·
        <.countdown
          :if={@open?}
          id="poll-left"
          closes_at={@poll.closes_at}
          now={@page.now}
          format="seconds"
        />
        <span :if={!@open?}>
          Closed
          <RegentsWeb.Keyfleet.Time.local id="poll-closed-at" at={Polls.closed_at(@poll)} as={:stamp} />
        </span>
      </p>

      <.notice notice={@notice} />

      <div class="polls-grid">
        <section id="poll-choices" class="polls-panel" aria-labelledby="poll-choices-title">
          <h2 id="poll-choices-title">{if @open?, do: "Choices", else: "Results"}</h2>

          <%!-- Always on the page, so the line a vote brings is read out as it
               appears in place of the form that held focus. --%>
          <div id="poll-my-vote-said" class="polls-said" role="status">
            <p :if={@page.my_vote} id="poll-my-vote" class="polls-detail">
              Your Key voted for {@page.my_vote.choice}.
            </p>
          </div>

          <.form
            :if={@can_vote?}
            for={%{}}
            as={:vote}
            id="poll-vote-form"
            class="polls-form"
            phx-submit="cast_vote"
          >
            <fieldset class="polls-choices">
              <legend>Your vote</legend>
              <label :for={choice <- @poll.choices}>
                <input type="radio" name="vote[choice]" value={choice} required />
                {choice}
              </label>
            </fieldset>
            <Regent.Primitives.field
              :let={field}
              id="poll-vote-reason"
              class="polls-field"
              label="Reason (optional)"
            >
              <input id={field.id} name="vote[reason]" maxlength="500" autocomplete="off" />
            </Regent.Primitives.field>
            <div class="sticky-actions">
              <Regent.Primitives.button type="submit">Vote</Regent.Primitives.button>
            </div>
          </.form>

          <ul :if={@open? and not @can_vote?} class="polls-options">
            <li :for={choice <- @poll.choices}>{choice}</li>
          </ul>

          <p :if={@open?} id="poll-votes-so-far" class="polls-detail">
            <Count.count id="poll-votes-count" value={@poll.votes_cast} one="vote" many="votes" />
            so far. The count for each choice shows when the poll closes.
          </p>

          <div :if={not @open?} id="poll-results">
            <p class="polls-detail">{result(@poll.totals)}</p>
            <ul class="polls-totals">
              <li
                :for={total <- @poll.totals}
                data-winner={to_string(total.choice in leaders(@poll.totals))}
              >
                <span>{total.choice}</span>
                <span>{counted(total.votes, "vote", "votes")}</span>
              </li>
            </ul>
          </div>

          <Regent.Primitives.button
            :if={@open? and @starter?}
            id="poll-end"
            type="button"
            variant="quiet"
            phx-click="end_poll"
            data-confirm="End this poll now? It takes no more votes."
            data-confirm-action="End"
          >
            End poll
          </Regent.Primitives.button>
        </section>

        <div class="polls-side">
          <section
            :if={@poll.notes}
            id="poll-notes"
            class="polls-panel"
            aria-labelledby="poll-notes-title"
          >
            <h2 id="poll-notes-title">
              Notes
              <Regent.Primitives.tip id="poll-notes-tip" label="About these notes">
                The poll’s starter wrote these for this fleet’s Key holders.
              </Regent.Primitives.tip>
            </h2>
            <p class="polls-reason">{@poll.notes}</p>
          </section>

          <section
            :if={@page.votes != []}
            id="poll-each-vote"
            class="polls-panel"
            aria-labelledby="poll-each-vote-title"
          >
            <h2 id="poll-each-vote-title">Votes</h2>
            <ul class="polls-votes">
              <li :for={vote <- @page.votes}>
                <.link patch={KeyLinks.key_path(@page.fleet_id, vote.token_id)}>
                  {ActivityLines.key_name(vote.token_id, vote.agent)}
                </.link>
                chose {vote.choice}
                <span :if={vote.reason} class="polls-reason">“{vote.reason}”</span>
              </li>
            </ul>
          </section>
        </div>
      </div>
    </article>
    """
  end

  attr :id, :string, required: true
  attr :page, :map, required: true

  # What anyone who isn't one of the fleet's members is shown of its polls.
  defp locked(assigns) do
    ~H"""
    <article id={@id} class="polls-page">
      <header class="polls-heading">
        <p class="polls-kicker">
          <.link patch={Regents.Keyfleet.Fleets.path(@page.fleet_id)}>{@page.fleet_name}</.link>
        </p>
        <h1 tabindex="-1">Polls</h1>
      </header>
      <section id="polls-locked" class="polls-panel" aria-labelledby="polls-locked-title">
        <h2 id="polls-locked-title">Keys only</h2>
        <.footnote
          class="polls-detail"
          text={
            if @page.refreshing?,
              do: KeysLive.refreshing(),
              else: "Only this fleet’s Key holders can see its polls."
          }
          tip_id="polls-who-tip"
          tip_label="About who sees polls"
        >
          People and agents holding a Key, or a shard of one. An agent paired with a Key holder
          takes part as their Key.
        </.footnote>
        <Regent.Primitives.button
          :if={not @page.signed_in?}
          id="polls-sign-in"
          type="button"
          data-account-target="sign-in"
        >
          Sign in
        </Regent.Primitives.button>
        <div :if={@page.signed_in?} class="polls-locked__actions">
          <.link
            patch={Regents.Keyfleet.Fleets.path(@page.fleet_id)}
            class="rg-button rg-button--secondary"
          >
            Back to {@page.fleet_name}
          </.link>
          <a href="/account#account-keyfleet" class="rg-button rg-button--quiet">
            View your Keys
          </a>
        </div>
      </section>
    </article>
    """
  end

  # Someone holding a Key who hasn't started a poll in the last day has the
  # form above the list.
  defp can_ask?(%{voter: voter, last_started: nil}), do: voter != nil
  defp can_ask?(_page), do: false

  attr :page, :map, required: true
  attr :title, :string, required: true

  defp detail_heading(assigns) do
    ~H"""
    <header class="polls-heading">
      <p class="polls-kicker">
        <.link patch={Regents.Keyfleet.Fleets.path(@page.fleet_id)}>{@page.fleet_name}</.link>
        · <.link patch={list_path(@page.fleet_id)}>Polls</.link>
      </p>
      <h1 tabindex="-1">{@title}</h1>
    </header>
    """
  end

  attr :notice, :map, required: true

  # A refusal is an alert, so a screen reader reads it out as it appears.
  defp notice(assigns) do
    ~H"""
    <p
      :if={@notice}
      id="polls-notice"
      role={@notice.tone == :error && "alert"}
      class="polls-notice"
      phx-hook="MotionRefusal"
      data-refused={@notice.tone == :error}
    >
      {@notice.message}
    </p>
    """
  end

  attr :id, :string, required: true

  defp unreadable(assigns) do
    ~H"""
    <article id={@id} class="polls-page">
      <header class="polls-heading">
        <p class="polls-kicker">Keyfleet</p>
        <h1 tabindex="-1">Polls</h1>
      </header>
      <section class="polls-panel">
        <.load_failed />
      </section>
    </article>
    """
  end

  attr :id, :string, required: true

  defp missing_fleet(assigns) do
    ~H"""
    <article id={@id} class="polls-page">
      <header class="polls-heading">
        <p class="polls-kicker">Keyfleet</p>
        <h1 tabindex="-1">Polls</h1>
      </header>
      <section class="polls-panel">
        <h2>This fleet doesn’t exist.</h2>
        <a href="/keyfleet/app" class="rg-button rg-button--secondary">See the fleets</a>
      </section>
    </article>
    """
  end

  @doc "The address of a fleet's polls."
  def list_path(fleet_id), do: "#{Regents.Keyfleet.Fleets.path(fleet_id)}/polls"

  @doc "The address of one poll."
  def poll_path(fleet_id, poll_id),
    do: "#{Regents.Keyfleet.Fleets.path(fleet_id)}/polls/#{poll_id}"

  @doc """
  The polls page named in the address, with the page listening to what it
  shows. Leaving the polls clears it.
  """
  def read_polls(socket, :polls, %{"fleet_id" => fleet_id}) do
    socket
    |> assign(polls_notice: nil, poll_form: start_form())
    |> read(fleet_id, nil, :unreadable)
  end

  def read_polls(socket, :poll, %{"fleet_id" => fleet_id, "poll_id" => poll_id}) do
    socket
    |> assign(polls_notice: nil, poll_form: nil)
    |> read(fleet_id, poll_id, :unreadable)
  end

  # The Worldline shows no polls page, but hears the fleet's polls start
  # (`RegentsWeb.Keyfleet.WorldlineLive`), as only its members do.
  def read_polls(socket, :worldline, %{"fleet_id" => fleet_id}) do
    socket
    |> listen(heard(socket, fleet_id, nil))
    |> stop_clock()
    |> assign(polls: nil, poll_form: nil, polls_notice: nil)
  end

  def read_polls(socket, _route_id, _params) do
    socket
    |> listen([])
    |> stop_clock()
    |> assign(polls: nil, poll_form: nil, polls_notice: nil)
  end

  @doc """
  The polls on show, read again for this reader: after a change to them, to
  who holds the fleet's Keys, or a press. A read again that fails keeps what
  the page shows and looks again a moment later, so a poll that closed
  meanwhile still comes to show its result.
  """
  def refresh(%{assigns: %{polls: %{fleet_id: fleet_id, poll_id: poll_id} = shown}} = socket),
    do: read(socket, fleet_id, poll_id, shown)

  def refresh(socket), do: socket

  # The page listens to the address's own topic before it reads, so a change
  # made between the read and the listening is still heard. A first read
  # that fails says the page couldn't be loaded.
  defp read(socket, fleet_id, poll_id, failed) do
    socket =
      listen(socket, Enum.uniq(socket.assigns.polls_topics ++ heard(socket, fleet_id, poll_id)))

    case {PageRead.run("polls", fn -> page(socket, fleet_id, poll_id) end), failed} do
      {{:ok, page}, _failed} ->
        socket |> assign(:polls, page) |> listen(topics(page)) |> start_clock()

      {{:error, _failure}, :unreadable} ->
        socket |> assign(:polls, :unreadable) |> listen([]) |> stop_clock()

      {{:error, _failure}, shown} ->
        socket |> listen(topics(shown)) |> look_again()
    end
  end

  # Only the fleet's members hear of its polls.
  defp heard(socket, fleet_id, poll_id) do
    cond do
      not ShellLive.may_read?(socket, fleet_id, :polls) -> []
      poll_id -> [Polls.topic(poll_id)]
      true -> [Polls.fleet_topic(fleet_id)]
    end
  end

  # The page as this reader may see it. Only the fleet's members read its
  # polls; anyone else is told they are for the fleet's Keys. Who a member
  # takes part as is read only while the fleet's Key ownership is fresh, as
  # the actions themselves read it.
  defp page(socket, fleet_id, poll_id) do
    case Fleets.get_fleet!(fleet_id) do
      nil -> %{kind: :missing, fleet_id: fleet_id, fleet_name: nil, poll_id: poll_id}
      fleet -> page(socket, fleet, poll_id, ShellLive.may_read?(socket, fleet_id, :polls))
    end
  end

  defp page(socket, fleet, poll_id, readable?) do
    actor = ShellLive.human_actor(socket)
    fresh? = actor != nil and Chain.fresh?(fleet.id)

    page = %{
      fleet_id: fleet.id,
      fleet_name: fleet.name,
      poll_id: poll_id,
      now: DateTime.utc_now(),
      voter: if(readable? and fresh?, do: Polls.voter(actor, fleet.id))
    }

    cond do
      not readable? ->
        Map.merge(page, %{
          kind: :locked,
          signed_in?: actor != nil,
          refreshing?: actor != nil and fleet.manager_address != nil and not fresh?
        })

      poll_id ->
        poll_page(page, ShellLive.reads_as(socket, fleet.id))

      true ->
        list_page(page, ShellLive.reads_as(socket, fleet.id))
    end
  end

  # The polls are read with the class the page already read (`read_as`).
  defp list_page(page, read_as) do
    listed = Polls.list_polls!(page.fleet_id, read_as)
    agents = WorkspacePage.agent_names(Enum.map(listed, & &1.acting_agent_wallet))
    last = page.voter && Polls.last_started!(page.fleet_id, page.voter.key, read_as)

    Map.merge(page, %{
      kind: :list,
      polls: Enum.map(listed, &shown(&1, page.now, agents)),
      last_started: last && %{inserted_at: last.inserted_at}
    })
  end

  defp poll_page(page, read_as) do
    case Polls.get_poll!(page.fleet_id, page.poll_id, read_as) do
      nil ->
        Map.merge(page, %{kind: :poll, poll: nil, my_vote: nil, votes: []})

      poll ->
        agents = WorkspacePage.agent_names([poll.acting_agent_wallet])

        page
        |> Map.merge(%{kind: :poll, poll: shown(poll, page.now, agents)})
        |> Map.merge(holders(page.voter, read_as[:actor], page.fleet_id, page.poll_id))
    end
  end

  # A poll as the page shows it: its question, choices, the starter's notes,
  # Key and times, how many votes it has drawn, whether it is open at `now`
  # and, once closed, each choice's count. `now` is taken before the poll is
  # read, so a poll open at `now` has no result yet and one closed has it. A
  # poll an agent started names the agent beside its Key.
  defp shown(%Poll{} = poll, now, agents) do
    %{
      id: poll.id,
      question: poll.question,
      choices: poll.choices,
      notes: poll.notes,
      started_by_key: poll.started_by_key,
      agent: agents[poll.acting_agent_wallet],
      votes_cast: poll.votes_cast,
      totals: poll.totals,
      closes_at: poll.closes_at,
      ended_at: poll.ended_at,
      inserted_at: poll.inserted_at,
      open?: Polls.open?(poll, now)
    }
  end

  # What the reader reads of a poll as its own Key: the Key's own vote and,
  # once the poll closes, every Key's vote and why.
  defp holders(nil, _actor, _fleet_id, _poll_id), do: %{my_vote: nil, votes: []}

  defp holders(_voter, actor, fleet_id, poll_id) do
    %{
      my_vote: my_vote(Polls.my_vote!(fleet_id, poll_id, actor: actor)),
      votes: votes(Polls.votes_in_poll!(fleet_id, poll_id, actor: actor))
    }
  end

  defp my_vote(nil), do: nil
  defp my_vote(vote), do: %{choice: vote.choice}

  # Each Key's vote, naming the agent that cast it.
  defp votes(votes) do
    agents = WorkspacePage.agent_names(Enum.map(votes, & &1.acting_agent_wallet))

    Enum.map(
      votes,
      &%{
        token_id: &1.token_id,
        agent: agents[&1.acting_agent_wallet],
        choice: &1.choice,
        reason: &1.reason
      }
    )
  end

  # The fleet's polls as they start and end, and each active one's votes; or
  # the one poll's votes and its ending.
  defp topics(%{kind: :list, fleet_id: fleet_id, polls: polls}),
    do: [Polls.fleet_topic(fleet_id) | for(poll <- polls, poll.open?, do: Polls.topic(poll.id))]

  defp topics(%{kind: :poll, poll: %{id: id}}), do: [Polls.topic(id)]
  defp topics(_page), do: []

  defp listen(socket, topics) do
    if connected?(socket) and topics != socket.assigns.polls_topics do
      Enum.each(
        socket.assigns.polls_topics -- topics,
        &Phoenix.PubSub.unsubscribe(Regents.PubSub, &1)
      )

      Enum.each(
        topics -- socket.assigns.polls_topics,
        &Phoenix.PubSub.subscribe(Regents.PubSub, &1)
      )

      assign(socket, :polls_topics, topics)
    else
      socket
    end
  end

  # The page's one timer. The countdown is drawn in the browser
  # (`RegentsWeb.Keyfleet.Components.Countdown`); the server looks at the clock only
  # for the next poll on show to close, each page at a moment of its own up to
  # two seconds after it, so a crowd on one poll never reads at once.
  defp start_clock(socket) do
    socket = stop_clock(socket)

    case connected?(socket) && next_close(socket.assigns.polls) do
      ms when is_integer(ms) ->
        assign(socket, :polls_clock, Process.send_after(self(), :polls_tick, ms + jitter()))

      _none ->
        socket
    end
  end

  defp next_close(%{kind: :poll, poll: %{open?: true} = poll, now: now}),
    do: until(poll.closes_at, now)

  defp next_close(%{kind: :list, polls: polls, now: now}) do
    case for(poll <- polls, poll.open?, do: until(poll.closes_at, now)) do
      [] -> nil
      waits -> Enum.min(waits)
    end
  end

  defp next_close(_page), do: nil

  defp jitter, do: :rand.uniform(2_001) - 1

  defp stop_clock(%{assigns: %{polls_clock: clock}} = socket) when is_reference(clock) do
    Process.cancel_timer(clock)
    assign(socket, :polls_clock, nil)
  end

  defp stop_clock(socket), do: socket

  defp look_again(socket) do
    socket = stop_clock(socket)

    if connected?(socket),
      do: assign(socket, :polls_clock, Process.send_after(self(), :polls_tick, @look_again_ms)),
      else: socket
  end

  defp until(at, now), do: max(DateTime.diff(at, now, :millisecond), 0) + 50

  @doc """
  Takes part in the poll page on show as `actor`, the way its boxes and
  buttons do and its browser tools do: `:start` a poll from the list
  (question, choices one per line, notes, minutes), and on a poll's page
  `:vote` (choice, reason) or `:end` it. Answers what the poll's action
  answers.
  """
  def act(:start, %{kind: :list, fleet_id: fleet_id}, input, actor) do
    input
    |> Map.take(["question", "notes", "minutes"])
    |> Map.reject(fn {_field, value} -> value == "" end)
    |> Map.merge(%{"fleet_id" => fleet_id, "choices" => choices(input["choices"])})
    |> Polls.start_poll(actor: actor)
  end

  def act(:vote, %{kind: :poll, fleet_id: fleet_id, poll: %{id: poll_id}}, input, actor) do
    input
    |> Map.take(["choice", "reason"])
    |> Map.reject(fn {_field, value} -> value == "" end)
    |> Map.merge(%{"fleet_id" => fleet_id, "poll_id" => poll_id})
    |> Polls.cast_vote(actor: actor)
  end

  # Ending a poll reads it again, as the person ending it.
  def act(:end, %{kind: :poll, fleet_id: fleet_id, poll: %{id: poll_id}}, _input, actor) do
    with {:ok, %Poll{} = poll} <- Polls.get_poll(fleet_id, poll_id, actor: actor),
         do: Polls.end_poll(poll, fleet_id, actor: actor)
  end

  @doc "The refusal code each press answers with when its error says no more."
  def default_code(:end), do: "not_starter"
  def default_code(_action), do: "poll_needs_key"

  @doc "What the polls pages do with a poll started or ended, and a vote."
  def handle_event(
        "start_poll",
        %{"poll" => params},
        %{assigns: %{polls: %{kind: :list} = page}} = socket
      )
      when is_map(params) do
    if choices_too_long?(params) do
      too_long =
        {"The choices are too long: #{Rules.grouped(@longest_choices)} characters at most.",
         [validation: :length, kind: :max, count: @longest_choices]}

      {:noreply, assign(socket, poll_form: form(params, choices: too_long), polls_notice: nil)}
    else
      case act(:start, page, params, ShellLive.human_actor(socket)) do
        {:ok, poll} ->
          {:noreply, push_patch(socket, to: poll_path(poll.fleet_id, poll.id))}

        {:error, error} ->
          {:noreply, form_refused(socket, params, error)}
      end
    end
  end

  def handle_event(event, params, %{assigns: %{polls: %{kind: :poll, poll: %{}}}} = socket)
      when event in ["end_poll", "cast_vote"] do
    action = if event == "end_poll", do: :end, else: :vote

    case act(action, socket.assigns.polls, vote(params), ShellLive.human_actor(socket)) do
      {:error, error} -> {:noreply, socket |> refused(error, default_code(action)) |> refresh()}
      _done -> {:noreply, socket |> assign(:polls_notice, nil) |> refresh()}
    end
  end

  # A press the page no longer shows the poll for, or a poll sent without its boxes.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp vote(%{"vote" => input}) when is_map(input), do: input
  defp vote(_params), do: %{}

  @doc """
  A change to the polls on show, and the page's one timer: the next poll on
  show closing, or a look again after a read that failed.
  """
  def handle_info(%Broadcast{event: event}, socket)
      when event in ["poll_changed", "polls_changed"],
      do: {:noreply, refresh(socket)}

  def handle_info(:polls_tick, socket) do
    socket = assign(socket, :polls_clock, nil)
    {:noreply, refresh(socket)}
  end

  # A refusal is said above the poll.
  defp refused(%{assigns: %{polls: %{fleet_id: fleet_id}}} = socket, error, code) do
    {_code, message} = refusal(error, fleet_id, code)
    assign(socket, :polls_notice, %{tone: :error, message: message})
  end

  # A question, choices or notes that break the rules are said under their
  # box instead; what the person typed stays in the boxes either way.
  defp form_refused(%{assigns: %{polls: %{fleet_id: fleet_id}}} = socket, params, error) do
    case refusal(error, fleet_id, default_code(:start)) do
      {"invalid_poll", _message} ->
        assign(socket, poll_form: form(params, field_errors(error)), polls_notice: nil)

      {_code, message} ->
        assign(socket,
          poll_form: form(params, []),
          polls_notice: %{tone: :error, message: message}
        )
    end
  end

  # The boxes whose rules an action's error names.
  defp field_errors(%Ash.Error.Invalid{errors: errors}) do
    for %{field: field} <- errors,
        field in [:question, :choices, :notes],
        uniq: true,
        do: {field, {"breaks its rule", []}}
  end

  defp field_errors(_error), do: []

  @doc """
  `{code, message}` for a poll action's error: the agent API's code
  (`RegentsWeb.Keyfleet.PollRefusal`) and the words the page says it in.
  """
  def refusal(error, fleet_id, code) do
    {_status, code} = PollRefusal.of(error, fleet_id, code)
    {code, message(code)}
  end

  defp message("ownership_refreshing"), do: KeysLive.refreshing()

  defp message("poll_needs_key"),
    do:
      "Only the people and agents holding this fleet’s Keys, or a shard of one, start and vote in its polls."

  defp message("poll_unknown"), do: "This fleet has no such poll."
  defp message("poll_closed"), do: "This poll has closed."

  defp message("poll_limit_reached"),
    do: "Your Key started a poll in the last day. Each Key starts one poll a day."

  defp message("not_starter"), do: "Only the Key that started this poll can end it."
  defp message("choice_unknown"), do: "Choose one of the poll’s choices."
  defp message("vote_conflict"), do: "Your Key has already voted in this poll."

  defp message("invalid_poll"),
    do:
      "A question is up to 200 characters on one line, with 2 to 10 different choices of up to 100 characters, notes of up to 2,000, and 1 to 60 minutes open. A reason is up to 500 characters."

  # Only what was typed goes back in the boxes.
  defp form(params, errors) do
    params
    |> Map.filter(fn {_field, value} -> is_binary(value) end)
    |> to_form(as: "poll", errors: errors)
  end

  defp start_form, do: form(%{"minutes" => "30"}, [])

  # Each line typed is one choice.
  defp choices(text) when is_binary(text) do
    text
    |> String.split(["\r\n", "\n"])
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp choices(_missing), do: []

  defp choices_box, do: BoxLimit.maxlength(@longest_choices)

  defp choices_too_long?(%{"choices" => text}) when is_binary(text),
    do: BoxLimit.too_long?(text, @longest_choices)

  defp choices_too_long?(_params), do: false

  # A box typed past its longest says so; one whose rule a submitted poll
  # broke says the rule.
  defp errors(field, rule) do
    for {message, opts} <- field.errors,
        uniq: true,
        do: if(opts[:validation] == :length, do: message, else: rule)
  end

  @doc """
  A closed poll's result in words: the choice with the most votes, the
  choices tied for the most, or that nobody voted.
  """
  def result(totals) do
    case leaders(totals) do
      [] -> "No votes"
      [choice] -> "Most votes: #{choice}"
      tied -> "Tied: #{Enum.join(tied, ", ")}"
    end
  end

  defp leaders(totals) do
    case totals |> Enum.map(& &1.votes) |> Enum.max(fn -> 0 end) do
      0 -> []
      most -> for %{choice: choice, votes: ^most} <- totals, do: choice
    end
  end

  defp length_label(1), do: "1 minute"
  defp length_label(60), do: "1 hour"
  defp length_label(minutes), do: "#{minutes} minutes"

  defp lengths, do: @lengths
end
