defmodule RegentsWeb.Keyfleet.WorldlinePage do
  @moduledoc """
  A fleet's worldline, read: everything that happened in it, as events in
  time order, each linking to the page it happened on. Nothing is stored for
  it; every page is read fresh from the records the fleet already keeps.

  ## Sources

  Each source is read as its own policy lets the reader read it
  (`Regents.Keyfleet.Access`):

    * `:posts`: posts and room namings in the rooms the reader reads
      (`Regents.Keyfleet.Rooms`). Keys' threads and direct messages are never read.
    * `:changes`: the workspace's notable changes (`Regents.Keyfleet.Graph`), for
      whoever reads the workspace.
    * `:pushes`: branches and tags moved in the fleet's code
      (`Regents.Keyfleet.Code.Push`), for whoever reads the code.
    * `:notebooks`: notebooks changed, as their daily copies record it
      (`Regents.Keyfleet.Notebooks.Backup`), for whoever reads the workspace.
    * `:polls` and `:stopped`: polls started, and stopped as they were
      ended or closed (`Regents.Keyfleet.Polls.Poll`), for whoever reads the polls.
    * `:opened` and `:closed`: proposals opened, and closed as their ballots
      stopped (`Regents.Keyfleet.Proposals.Proposal`), for anyone.
    * `:votes`, `:executed` and `:cancelled`: votes on proposals, and
      proposals carried out or cancelled (`Regents.Keyfleet.Proposals`), for anyone.
    * `:keys`: Keys bought or given, and Keys changing hands
      (`Regents.Keyfleet.Keys.KeyAttachment`), for anyone.
    * `:shards`: shards lent and ended (`Regents.Keyfleet.Keys.ShardEvent`), for
      anyone.
    * `:present`: Keys marked present on their own (`Regents.Keyfleet.Keys.Presence`),
      for anyone.
    * `:treasury`: the daily split released and rewards claimed
      (`Regents.Keyfleet.Treasury.Event`), for anyone.
    * `:projects`: projects started (`Regents.Keyfleet.Projects.Project`), for
      anyone.

  The chain's records carry when they were read, not their block's time.

  ## Whose events

  `by/1` reads a filter's words. With `{:key, n}` every source keeps what Key
  n did and what was done to it; with `{:wallet, wallet}`, what that wallet
  did, or an agent with that wallet did as a Key, and what the Keys it holds
  now did (`Regents.Keyfleet.Preparations.DoneBy`). Each source keeps them in its own
  read, so paging stays whole.

  ## Events

  Every event is `%{id:, at:, trail:, kind:, key:, place:, what:, title:, path:, live?:}`.
  `id` is stable across reads and `at` is when it happened. `trail` is where
  it is drawn: `"workspace"`, `"code"` or `"notebooks"`, the planets'
  paths; `"room:<slug>"` for a room's posts; or `"line"` for everything
  fleet-wide, on the worldline itself. `kind` says what it was: `:post`,
  `:room_named`, `:change`, `:push`, `:notebook`, `:poll`, `:poll_stopped`,
  `:proposal_opened`, `:proposal_closed`, `:vote`, `:executed`, `:cancelled`,
  `:sold`, `:given`, `:transfer`, `:shard_lent`, `:shard_ended`, `:present`,
  `:daily_split`, `:claimed` or `:project`. `key` is the Key that did it,
  nil when none did or it is not known. `place` is a room's line's place in
  its room, counting from 1, and nil for every other event. `what` is a word
  or two saying what it was, `title` its words, and `path` the page it links
  to: a page of this site's live view when `live?`, or a page opened in full
  otherwise.

  ## Paging

  Each source is read newest first from its own place, `limit` at a time.
  Below the oldest time a full read reached, that source may hold more it has
  not read, so a page keeps every source's events down to the latest of
  those times, and each source carries on from the last event it kept. A page
  is never empty while anything older is left, never repeats an event, and
  its cursor is nil when nothing older is.

  The first page fixes where every walk begins: the time it was read, by the
  database's clock, and for the logs kept in record order (the workspace's
  and the chain's) the newest record read. Proposals and polls close by that
  time. Anything newer is left to a fresh read.

  The cursor holds atoms, tuples and times, and `page/3` trusts its shape: it
  must never leave the server.
  """

  alias Regents.Keyfleet.{
    Access,
    Code,
    Graph,
    Keys,
    Notebooks,
    Polls,
    Projects,
    Proposals,
    Rooms,
    Treasury
  }

  alias Regents.Repo

  alias Regents.Keyfleet.Fleets.{Presets, Rules}

  alias RegentsWeb.Keyfleet.{
    ActivityLines,
    BoxLimit,
    DirectoryMD,
    KeyLinks,
    PollsLive,
    ProjectPage,
    ProposalsPage,
    WorkspacePage
  }

  @type source ::
          :posts
          | :changes
          | :pushes
          | :notebooks
          | :polls
          | :stopped
          | :opened
          | :closed
          | :votes
          | :executed
          | :cancelled
          | :keys
          | :shards
          | :present
          | :treasury
          | :projects
  @type cursor :: %{optional(source()) => term()}
  @type by :: nil | {:key, pos_integer()} | {:wallet, String.t()}
  @type event :: %{
          id: String.t(),
          at: DateTime.t(),
          trail: String.t(),
          kind: atom(),
          key: pos_integer() | nil,
          place: pos_integer() | nil,
          what: String.t(),
          title: String.t(),
          path: String.t(),
          live?: boolean()
        }

  # Each source and the part of the fleet whose readers read it; the rooms'
  # own policy keeps each room's posts to its readers.
  @sources [
    posts: nil,
    changes: :workspace,
    pushes: :code,
    notebooks: :workspace,
    polls: :polls,
    stopped: :polls,
    opened: nil,
    closed: nil,
    votes: nil,
    executed: nil,
    cancelled: nil,
    keys: nil,
    shards: nil,
    present: nil,
    treasury: nil,
    projects: nil
  ]

  # The sources kept in record order, whose walk begins at their newest.
  @from_newest [:changes, :votes, :executed, :cancelled, :keys, :shards, :present, :treasury]

  # The treasury's records told: the daily split run, and rewards claimed.
  @treasury_kinds [:daily_split_run, :claimed]

  @doc """
  A page of the fleet's worldline, oldest first: `%{events: events, cursor: cursor}`.

  `cursor` is nil for the newest page, or the cursor a page answered to read
  the one before it. Options: `:limit`, how many of each source's events are
  read at most (1 to 100), `:only`, the sources read on the newest page (all
  the reader reads by default), `:by`, whose events are kept (`by/1`;
  everyone's when nil), and `:actor` and `:context`, who reads it
  (`Regents.Keyfleet.Access.context/3`).
  """
  @spec page(String.t(), cursor() | nil, keyword()) :: %{
          events: [event()],
          cursor: cursor() | nil
        }
  def page(fleet_id, cursor, opts) do
    limit = Keyword.fetch!(opts, :limit)
    true = limit in 1..100
    read_as = Keyword.take(opts, [:actor, :context])
    only = Keyword.get(opts, :only, Keyword.keys(@sources))
    done_by = done_by(fleet_id, opts[:by])
    positions = cursor || start(Enum.filter(sources(fleet_id, read_as), &(&1 in only)))

    reads =
      Map.new(positions, fn {source, position} ->
        {source, read(source, fleet_id, position, limit, done_by, read_as)}
      end)

    floor = floor(reads, limit)

    {kept, cursor} =
      Enum.reduce(reads, {[], %{}}, fn {source, entries}, {kept, cursor} ->
        taken = Enum.take_while(entries, &(floor == nil or not DateTime.before?(&1.at, floor)))

        if length(entries) < limit and length(taken) == length(entries),
          do: {taken ++ kept, cursor},
          else:
            {taken ++ kept, Map.put(cursor, source, carry_on(taken, entries, positions[source]))}
      end)

    %{
      events: kept |> name(fleet_id, read_as) |> Enum.sort_by(&{stamp(&1.at), &1.id}),
      cursor: if(cursor == %{}, do: nil, else: cursor)
    }
  end

  @doc """
  Whose events a filter's words ask for: a Key by its number ("19", "Key 19",
  "#19" or "Key 1,234"), as `{:key, 19}`, or a wallet (0x and 40 hexadecimal
  digits, in any case), as `{:wallet, wallet}` in lower case. Blank asks for
  everyone's, as nil; anything else is `:error`, and so are words longer
  than `longest_filter/0`.
  """
  @spec by(String.t()) :: {:ok, by()} | :error
  def by(words) do
    too_long? = BoxLimit.too_long?(words, longest_filter())
    words = String.trim(words)
    key = Regex.run(~r/\A(?:key\s*)?#?\s*([1-9][0-9]{0,17})\z/i, String.replace(words, ",", ""))

    cond do
      too_long? -> :error
      words == "" -> {:ok, nil}
      Regex.match?(~r/\A0x[0-9a-f]{40}\z/i, words) -> {:ok, {:wallet, String.downcase(words)}}
      key -> {:ok, {:key, key |> List.last() |> String.to_integer()}}
      true -> :error
    end
  end

  @doc "The longest filter the Worldline reads (`RegentsWeb.Keyfleet.BoxLimit`)."
  def longest_filter, do: 100

  @doc "The sources the reader `read_as` names reads of the fleet's worldline."
  @spec sources(String.t(), keyword()) :: [source()]
  def sources(fleet_id, read_as) do
    class =
      get_in(read_as, [:context, :shared, :access, :class]) ||
        Access.class(read_as[:actor], fleet_id)

    for {source, part} <- @sources, part == nil or Access.enough?(class, :read, part), do: source
  end

  # What every read keeps: everything; a Key's events; or a wallet's, and
  # those of the Keys it holds now.
  defp done_by(_fleet_id, nil), do: %{}
  defp done_by(_fleet_id, {:key, key}), do: %{keys: [key]}

  defp done_by(fleet_id, {:wallet, wallet}) do
    keys = fleet_id |> Keys.keys_held_in_fleet!([wallet]) |> Enum.map(& &1.token_id)
    %{keys: keys, wallet: wallet}
  end

  # Where each walk begins: the database's clock, which stamps posts, one
  # microsecond past so that the time itself is included. The logs kept in
  # record order begin at their newest.
  defp start(sources) do
    %Postgrex.Result{rows: [[now]]} = Repo.query!("SELECT clock_timestamp()")
    now = DateTime.add(now, 1, :microsecond)
    Map.new(sources, &{&1, if(&1 in @from_newest, do: nil, else: {now, nil})})
  end

  # The latest of the oldest times the full reads reached, or nil when no read
  # came back full.
  defp floor(reads, limit) do
    reads
    |> Map.values()
    |> Enum.filter(&(length(&1) == limit))
    |> Enum.map(fn entries -> entries |> Enum.map(& &1.at) |> Enum.min(DateTime) end)
    |> Enum.max(DateTime, fn -> nil end)
  end

  # A source carries on from the last event it kept. One that kept none
  # carries on from where it was, or for a log's first read, just past the
  # newest record it read.
  defp carry_on([], [newest | _], nil), do: just_past(newest.position)
  defp carry_on([], _entries, position), do: position
  defp carry_on(taken, _entries, _position), do: List.last(taken).position

  defp just_past({block, log}), do: {block, log + 1}
  defp just_past(seq), do: seq + 1

  defp stamp(at), do: DateTime.to_unix(at, :microsecond)

  # Reading: each source answers its rows newest first, each as an entry
  # with its time and its place in its source.
  defp read(:posts, fleet_id, {at, id}, limit, done_by, read_as) do
    fleet_id
    |> Rooms.fleet_lines_before!(at, id, limit, done_by, read_as)
    |> Enum.map(&entry(:posts, &1, &1.inserted_at, {&1.inserted_at, &1.id}))
  end

  defp read(:changes, fleet_id, seq, limit, done_by, _read_as) do
    fleet_id
    |> Graph.notable_before!(seq, limit, done_by)
    |> Enum.map(&entry(:changes, &1, logged(&1.timestamp), &1.seq))
  end

  defp read(:pushes, fleet_id, {at, id}, limit, done_by, read_as) do
    fleet_id
    |> Code.pushes_before!(at, id, limit, done_by, read_as)
    |> Enum.map(&entry(:pushes, &1, &1.pushed_at, {&1.pushed_at, &1.id}))
  end

  defp read(:notebooks, fleet_id, {at, id}, limit, done_by, read_as) do
    fleet_id
    |> Notebooks.backups_changed_before!(at, id, limit, done_by, read_as)
    |> Enum.map(&entry(:notebooks, &1, &1.changed_at, {&1.changed_at, &1.id}))
  end

  defp read(:polls, fleet_id, {at, id}, limit, done_by, read_as) do
    fleet_id
    |> Polls.polls_started_before!(at, id, limit, done_by, read_as)
    |> Enum.map(&entry(:polls, &1, &1.inserted_at, {&1.inserted_at, &1.id}))
  end

  defp read(:stopped, fleet_id, {at, id}, limit, done_by, read_as) do
    fleet_id
    |> Polls.polls_stopped_before!(at, id, limit, done_by, read_as)
    |> Enum.map(&entry(:stopped, &1, &1.stopped_at, {&1.stopped_at, &1.id}))
  end

  defp read(:opened, fleet_id, {at, id}, limit, done_by, read_as) do
    fleet_id
    |> Proposals.proposals_opened_before!(at, id, limit, done_by, read_as)
    |> Enum.map(&entry(:opened, &1, &1.opened_at, {&1.opened_at, &1.id}))
  end

  defp read(:closed, fleet_id, {at, id}, limit, done_by, read_as) do
    fleet_id
    |> Proposals.proposals_closed_before!(at, id, limit, done_by, read_as)
    |> Enum.map(&entry(:closed, &1, &1.closes_at, {&1.closes_at, &1.id}))
  end

  defp read(:votes, fleet_id, seq, limit, done_by, read_as) do
    fleet_id
    |> Proposals.votes_recorded_before!(seq, limit, done_by, read_as)
    |> Enum.map(&entry(:votes, &1, &1.observed_at, &1.record_seq))
  end

  defp read(:executed, fleet_id, seq, limit, done_by, read_as) do
    fleet_id
    |> Proposals.executions_recorded_before!(seq, limit, done_by, read_as)
    |> Enum.map(&entry(:executed, &1, &1.observed_at, &1.record_seq))
  end

  defp read(:cancelled, fleet_id, seq, limit, done_by, read_as) do
    fleet_id
    |> Proposals.cancellations_recorded_before!(seq, limit, done_by, read_as)
    |> Enum.map(&entry(:cancelled, &1, &1.observed_at, &1.record_seq))
  end

  defp read(:keys, fleet_id, seq, limit, done_by, read_as) do
    fleet_id
    |> Keys.epochs_recorded_before!(seq, limit, done_by, read_as)
    |> Enum.map(&entry(:keys, &1, &1.observed_at, &1.record_seq))
  end

  defp read(:shards, fleet_id, seq, limit, done_by, read_as) do
    fleet_id
    |> Keys.shard_events_recorded_before!(
      seq,
      limit,
      done_by,
      [load: [:agent_profile]] ++ read_as
    )
    |> Enum.map(&entry(:shards, &1, &1.observed_at, &1.record_seq))
  end

  defp read(:present, fleet_id, place, limit, done_by, read_as) do
    {block, log} = place || {nil, nil}

    fleet_id
    |> Keys.presences_marked_before!(block, log, limit, done_by, read_as)
    |> Enum.map(&entry(:present, &1, &1.observed_at, {&1.block_number, &1.log_index}))
  end

  defp read(:treasury, fleet_id, seq, limit, done_by, read_as) do
    fleet_id
    |> Treasury.events_recorded_before!(@treasury_kinds, seq, limit, done_by, read_as)
    |> Enum.map(&entry(:treasury, &1, &1.observed_at, &1.record_seq))
  end

  defp read(:projects, fleet_id, {at, name}, limit, done_by, read_as) do
    fleet_id
    |> Projects.projects_started_before!(at, name, limit, done_by, read_as)
    |> Enum.map(&entry(:projects, &1, &1.inserted_at, {&1.inserted_at, &1.name}))
  end

  defp entry(source, row, at, position),
    do: %{source: source, row: row, at: at, position: position}

  # The log stamps every change in UTC.
  defp logged(timestamp) do
    {:ok, at, _offset} = DateTime.from_iso8601(timestamp)
    at
  end

  # Naming: what each source's events link to is looked up together for the
  # page, then each entry becomes its event. An event whose page is gone is
  # left out.
  defp name(entries, fleet_id, read_as) do
    by_source = Enum.group_by(entries, & &1.source, & &1.row)
    known = lookup(by_source, fleet_id, read_as)

    Enum.flat_map(entries, fn entry ->
      case event(entry.source, entry.row, fleet_id, known) do
        nil -> []
        event -> [Map.merge(event, %{at: entry.at, place: place(entry.source, entry.row)})]
      end
    end)
  end

  defp place(:posts, line), do: line.seq
  defp place(_source, _row), do: nil

  defp lookup(by_source, fleet_id, read_as) do
    %{
      items: titles(fleet_id, Enum.map(by_source[:changes] || [], &change/1), read_as),
      projects:
        if(by_source[:pushes] || by_source[:notebooks],
          do: Projects.projects!(fleet_id, read_as),
          else: []
        ),
      given?: by_source[:keys] != nil and Presets.given?(fleet_id)
    }
  end

  defp titles(_fleet_id, [], _read_as), do: %{}

  defp titles(fleet_id, changes, read_as) do
    ids = changes |> Enum.map(fn {_what, id} -> id end) |> Enum.uniq()
    fleet_id |> Graph.object_titles!(ids, read_as) |> Map.new(&{&1.id, &1.title})
  end

  defp event(:posts, line, fleet_id, _known) do
    %{
      id: "post:#{line.id}",
      trail: "room:#{line.room.slug}",
      kind: line.kind,
      key: line.as_key,
      what: line.room.name,
      title:
        if(line.kind == :room_named,
          do: "Named #{line.excerpt}",
          else: ActivityLines.plain(line.excerpt)
        ),
      path: KeyLinks.room_path(fleet_id, line.room.slug),
      live?: true
    }
  end

  defp event(:changes, change, fleet_id, known) do
    {what, id} = change(change)
    type = id |> String.split("#", parts: 2) |> hd()

    %{
      id: "change:#{change.seq}",
      trail: "workspace",
      kind: :change,
      key: author(change.actor),
      what: what,
      title:
        known.items[id] || type |> WorkspacePage.type_name() |> elem(0) |> String.capitalize(),
      path: WorkspacePage.item_path(fleet_id, id),
      live?: true
    }
  end

  defp event(:pushes, push, fleet_id, known) do
    case Enum.find(known.projects, &(&1.name == push.project)) do
      %{repository: repository} ->
        %{
          id: "push:#{push.id}",
          trail: "code",
          kind: :push,
          key: push.token_id,
          what: "Push",
          title: "#{moved(push.ref)} in #{push.project}",
          path: Code.commit_path(fleet_id, repository, push.head),
          live?: true
        }

      nil ->
        nil
    end
  end

  defp event(:notebooks, copy, fleet_id, known) do
    case Enum.find(known.projects, &(&1.name == copy.project)) do
      %{hub_project_id: space} when is_binary(space) ->
        %{
          id: "notebook:#{copy.id}",
          trail: "notebooks",
          kind: :notebook,
          key: if(copy.key && copy.key > 0, do: copy.key),
          what: "Notebook",
          title: copy.title,
          path:
            "/keyfleet/fleets/#{fleet_id}/notebooks/open?" <>
              URI.encode_query(to: Notebooks.notebook_path(space, copy.notebook_id)),
          live?: false
        }

      _no_space ->
        nil
    end
  end

  defp event(:polls, poll, fleet_id, _known) do
    %{
      id: "poll:#{poll.id}",
      trail: "line",
      kind: :poll,
      key: poll.started_by_key,
      what: "Poll",
      title: poll.question,
      path: PollsLive.poll_path(fleet_id, poll.id),
      live?: true
    }
  end

  defp event(:stopped, poll, fleet_id, _known) do
    %{
      id: "poll_stopped:#{poll.id}",
      trail: "line",
      kind: :poll_stopped,
      key: nil,
      what: "Poll ended",
      title: poll.question,
      path: PollsLive.poll_path(fleet_id, poll.id),
      live?: true
    }
  end

  defp event(:opened, proposal, fleet_id, _known) do
    %{
      id: "opened:#{proposal.id}",
      trail: "line",
      kind: :proposal_opened,
      key: proposal.author_key,
      what: "Opened",
      title: ActivityLines.proposal_name(proposal.number),
      path: ProposalsPage.detail_path(fleet_id, proposal.number),
      live?: true
    }
  end

  defp event(:closed, proposal, fleet_id, _known) do
    %{
      id: "closed:#{proposal.id}",
      trail: "line",
      kind: :proposal_closed,
      key: nil,
      what: "Closed",
      title: ActivityLines.proposal_name(proposal.number),
      path: ProposalsPage.detail_path(fleet_id, proposal.number),
      live?: true
    }
  end

  defp event(:votes, vote, fleet_id, _known) do
    keys = Enum.sort(vote.token_ids)

    with_keys =
      case keys do
        [_one] -> ""
        many -> " with #{Rules.keys(length(many))}"
      end

    %{
      id: "vote:#{vote.id}",
      trail: "line",
      kind: :vote,
      key: hd(keys),
      what: "Vote",
      title:
        "#{choice(vote.choice)}#{with_keys} on #{ActivityLines.proposal_name(vote.proposal_number)}",
      path: ProposalsPage.detail_path(fleet_id, vote.proposal_number),
      live?: true
    }
  end

  defp event(:executed, execution, fleet_id, _known) do
    %{
      id: "executed:#{execution.id}",
      trail: "line",
      kind: :executed,
      key: nil,
      what: "Carried out",
      title: ActivityLines.proposal_name(execution.proposal_number),
      path: ProposalsPage.detail_path(fleet_id, execution.proposal_number),
      live?: true
    }
  end

  defp event(:cancelled, cancellation, fleet_id, _known) do
    %{
      id: "cancelled:#{cancellation.id}",
      trail: "line",
      kind: :cancelled,
      key: nil,
      what: "Cancelled",
      title: ActivityLines.proposal_name(cancellation.proposal_number),
      path: ProposalsPage.detail_path(fleet_id, cancellation.proposal_number),
      live?: true
    }
  end

  defp event(:keys, epoch, fleet_id, known) do
    {kind, what, title} =
      cond do
        epoch.ownership_epoch > 1 -> {:transfer, "Transfer", "changed hands"}
        known.given? -> {:given, "Given", "given"}
        true -> {:sold, "Bought", "bought"}
      end

    %{
      id: "key:#{epoch.fleet_id}:#{epoch.record_seq}",
      trail: "line",
      kind: kind,
      key: epoch.token_id,
      what: what,
      title: "Key #{Rules.grouped(epoch.token_id)} #{title}",
      path: KeyLinks.page_path(fleet_id, epoch.token_id),
      live?: true
    }
  end

  defp event(:shards, shard, fleet_id, _known) do
    holder = shard_holder(shard)

    {kind, title} =
      cond do
        shard.kind == :issued -> {:shard_lent, "Lent to #{holder}"}
        shard.ended_by == shard.wallet -> {:shard_ended, "#{holder} stepped down"}
        true -> {:shard_ended, "Ended for #{holder}"}
      end

    %{
      id: "shard:#{shard.id}",
      trail: "line",
      kind: kind,
      key: shard.token_id,
      what: "Shard",
      title: title,
      path: KeyLinks.page_path(fleet_id, shard.token_id),
      live?: true
    }
  end

  defp event(:present, presence, fleet_id, _known) do
    %{
      id: "present:#{presence.id}",
      trail: "line",
      kind: :present,
      key: presence.token_id,
      what: "Present",
      title: "Key #{Rules.grouped(presence.token_id)} marked present",
      path: KeyLinks.page_path(fleet_id, presence.token_id),
      live?: true
    }
  end

  defp event(:treasury, record, fleet_id, _known) do
    {kind, what, title} =
      case record.kind do
        :daily_split_run -> {:daily_split, "Split", "Daily split released"}
        :claimed -> {:claimed, "Rewards", "Rewards claimed"}
      end

    %{
      id: "treasury:#{record.id}",
      trail: "line",
      kind: kind,
      key: nil,
      what: what,
      title: title,
      path: ProposalsPage.treasury_path(fleet_id),
      live?: true
    }
  end

  defp event(:projects, project, fleet_id, _known) do
    %{
      id: "project:#{project.name}",
      trail: "line",
      kind: :project,
      key: project.created_by_key,
      what: "Project",
      title: project.title,
      path: ProjectPage.path(fleet_id, project.name),
      live?: true
    }
  end

  # An agent by the name it signed in with, or else the wallet.
  defp shard_holder(%{agent_profile: %{name: name}}) when is_binary(name),
    do: DirectoryMD.visible(name)

  defp shard_holder(shard), do: RegentFormat.short_address(shard.wallet)

  defp choice(:yes), do: "Yes"
  defp choice(:no), do: "No"
  defp choice(:abstain), do: "Abstain"

  # What a workspace change did, in a word, and the item it links to.
  defp change(%{type: "object.created", brief: %{"object_type" => "review"} = brief}),
    do: {"Review", brief["task"]}

  defp change(%{type: "object.created", brief: brief}),
    do: {type_word(brief["object"]), brief["object"]}

  defp change(%{type: "relation.created", brief: brief}),
    do: {linked(brief["relation_type"]), brief["target"]}

  defp change(%{type: "patch.applied", brief: %{"object" => id} = brief}) do
    values = brief["values"]

    what =
      cond do
        brief["archived"] -> "Archived"
        brief["submitted"] -> "Submitted"
        brief["joins"] > 0 -> "Joined"
        brief["joins"] < 0 -> "Left"
        match?(%{"progress" => %{"new" => _}}, values) -> progress(values["progress"]["new"])
        match?(%{"status" => %{"new" => _}}, values) -> String.capitalize(values["status"]["new"])
        true -> "Edited"
      end

    {what, id}
  end

  defp type_word(id),
    do:
      id
      |> String.split("#", parts: 2)
      |> hd()
      |> WorkspacePage.type_name()
      |> elem(0)
      |> String.capitalize()

  defp linked("supports"), do: "Backed"
  defp linked("contradicts"), do: "Problem"
  defp linked("produces"), do: "Produced"

  defp progress("todo"), do: "To do"
  defp progress(progress), do: String.capitalize(progress)

  # A member writes as its Key; the workspace's own actors write as none.
  defp author(actor) do
    with {token_id, _kind, _wallet} <- Graph.Event.member(actor), do: token_id
  end

  defp moved("refs/heads/" <> branch), do: branch
  defp moved("refs/tags/" <> tag), do: "tag " <> tag
  defp moved(ref), do: ref
end
