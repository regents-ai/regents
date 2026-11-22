defmodule Regents.Keyfleet.Activity do
  @moduledoc """
  What has been happening in a fleet, newest first, read from the records the
  fleet already keeps: its rooms, its workspace, its keys, their shards and
  its proposals. Nothing is stored for it; every page is read fresh. The
  workspace's changes are told only to those who read the workspace
  (`Regents.Keyfleet.Access`); anyone else reads the rest.

  `page/3` answers a page of items and the cursor to read the next one with;
  `headline/2` answers the one item a fleet's card features, as anyone reads
  it.

  ## Items

  Every item is `%{id: id, at: at, kind: kind, facts: facts}`. `id` is stable
  across reads, `at` is when it happened, and `facts` holds what a sentence
  about it needs, with names already looked up. Three shapes recur:

    * a key: `%{token_id: 7, agent: "Ada" | nil}`. `agent` is the agent that
      did the thing, for posts and workspace changes. `nil` means a person,
      and always for a key a task was given to.
    * an item of the workspace: `%{id: "task#4", type: "task", title: title | nil}`,
      `title` nil when the item is no longer there. A finding with its title
      also carries `confidence`.
    * a room: `%{slug: slug, name: name, topic: topic | nil}`.

  The kinds and their facts:

    * `:post`: `room`, `by` (the key it was written as, with its writer's
      `wallet`; `token_id` is nil for a post written as no key, in the People
      and agents room before posting there needed one), `excerpt` (its start, up to 160 characters ending on
      a whole word with "…").
    * `:posts`: consecutive posts in one room, at most an hour apart, six
      hours from first to last and fifty in all: `room`, `count`, `keys` (up to
      three different writers, each as `by` is, newest first), `others` (how
      many more wrote), `excerpt` (of the newest).
    * `:room_named`: `room`, `by`, `topic` (what the room was named).
    * Workspace changes carry `by` (a key, or nil when the workspace itself
      made the change) and `item`:
      * `:created`: a new item of any type;
      * `:submitted`: the task was submitted for review;
      * `:progress`: the task's `progress` is now "todo", "doing", "blocked"
        or "done";
      * `:status`: the goal's `status` is now "open", "achieved" or "dropped";
      * `:revised`: a goal or service was edited;
      * `:joined` and `:left`: `by` joined the goal or task, or left it;
      * `:archived`.
    * `:reviewed`: `by`, `item` (the task reviewed) and `decision`
      ("accept" or "dispute").
    * `:linked`: `by`, `relation` ("supports", "contradicts" or "produces"),
      `source` and `target` (items): the source supports, contradicts or
      produces the target.
    * `:tasks`: a run of tasks one key added, by the same rules as `:posts`:
      `by` and `added` (how many it added).
    * `:changes`: a run of one change (`change`: `:archived`, `:submitted`
      or `:revised`) one key made to items of one type, by the same rules as
      `:posts`: `by`, `change`, `type` and `count`.
    * `:sale`: `token_ids`, the keys bought, lowest first: consecutive
      purchases are one item, by the same rules as `:posts`.
    * `:given`: the same, for a fleet whose Keys are given rather than sold
      (`Regents.Keyfleet.Fleets.Presets.given?/1`).
    * `:transfer`: `token_id`, a key that changed hands.
    * `:shard_issued`: `token_id`, `wallet`, `agent` (`%{id: id, name: name}`,
      or nil while no agent has signed in with the wallet) and `expires_at`.
      Issuing again to a wallet renews its shard, and reads the same.
    * `:shard_ended`: `token_id`, `wallet`, `agent`, and `stepped_down?`:
      true when the wallet ended its own shard, false when the key's owner
      did. A shard that runs out, or whose key changes hands, ends without an
      item.
    * `:proposed`: `number`, `proposer` (`%{wallet: wallet, token_id: n |
      nil}`, the lowest key the wallet holds today) and `calls`, how many
      calls the treasury makes if it is carried out.
    * `:votes`: consecutive votes on one proposal: `number`, and `yes`, `no`
      and `abstain`, each `%{count: keys, token_ids: up to three, lowest
      first}`; and `totals`, how the whole proposal stood when this was read,
      `%{yes: keys, no: keys, abstain: keys}`.
    * `:executed`: `number`.

  ## Times

  Chain records (key sales, shards, proposals, votes and executions) carry
  no block time, only when they were read, so records read together, as in a
  backfill, share one time. Workspace changes carry the time the workspace
  logged them, and posts the time they were written.

  ## Paging

  Each source is read newest first from its own place in the cursor and
  grouped on its own, and the sources are merged by time, and at the same
  time in a fixed order of sources. A source that has handed over all it
  read is read again from where it stopped, twice at most in one page: a
  page that would need a third read of one source ends there, short, with a
  cursor. So a page holds `limit` items or fewer, a page is never empty, and
  a cursor means more is left; nil means nothing older is.

  The first page fixes where the walk begins for every source: the time it
  was read for posts (by the database's clock, which stamps them), and one
  past the newest record it read for the workspace, keys, shards and
  proposals. Everything recorded after the first page is left to a fresh
  read, so walking the pages with the cursors answered gives every item
  once, in the same order as one larger read made when the first page was.

  The cursor holds atoms, tuples and times, and `page/3` trusts its shape: it
  must never leave the server. Keep it in the process that read the page (a
  LiveView's assigns) and hand it back unchanged.

  ## For pages that show it live

  When something new happens, read the first page again rather than the
  pages after it, and read it once for a burst of changes to one fleet, not
  once per change.
  """

  alias Regents.Keyfleet.Access
  alias Regents.Keyfleet.Agents
  alias Regents.Keyfleet.Fleets.Presets
  alias Regents.Keyfleet.Graph
  alias Regents.Keyfleet.Keys
  alias Regents.Keyfleet.Proposals
  alias Regents.Keyfleet.Rooms
  alias Regents.Repo

  @type position :: nil | integer() | {DateTime.t(), term()}
  # A reader who doesn't read the workspace walks no `:graph`.
  @type cursor :: %{
          required(:posts) => position(),
          optional(:graph) => position(),
          required(:keys) => position(),
          required(:shards) => position(),
          required(:proposals) => position()
        }
  @type item :: %{id: String.t(), at: DateTime.t(), kind: atom(), facts: map()}

  # The sources, in the order they come in when their items share a time.
  @sources [:proposals, :keys, :shards, :graph, :posts]
  @page 30
  # Grouped sources read more rows than a page holds, and a group is capped
  # below the rows read, so a full read always holds a whole group to keep.
  # A source is read at most this many times for one page.
  @reads_per_page 2
  @posts_read 200
  @graph_read 200
  @votes_read 100
  @keys_read 100
  @group_cap 50
  @post_gap 3_600_000_000
  @post_span 21_600_000_000
  @listed_keys 3
  # The changes a run of which, by one key to items of one type, is one item.
  @repeated [:archived, :submitted, :revised]
  @recent 7 * 86_400

  @doc """
  A page of the fleet's activity, newest first: `%{items: items, cursor: cursor}`.

  `cursor` is nil for the newest page, or the cursor a page answered to read
  the one after it. Options: `:limit`, the most items a page holds (1 to
  #{@page}, #{@page} by default), `:actor`, who reads it, and `:context`, the
  class already read for them (`Regents.Keyfleet.Access.context/3`). Posts in rooms
  other than the ones anyone reads, and the workspace's changes, show only to
  the people and agents holding the fleet's keys or a shard of one.
  """
  @spec page(String.t(), cursor() | nil, keyword()) :: %{items: [item()], cursor: cursor() | nil}
  def page(fleet_id, cursor, opts \\ []) do
    limit = Keyword.get(opts, :limit, @page)
    true = limit in 1..@page
    read_as = Keyword.take(opts, [:actor, :context])
    sources = sources(fleet_id, read_as)
    positions = cursor || start()

    # A read that came back full leaves out its last entry, which may be the
    # start of a group it did not read to the end.
    fetch = fn source, position, reads ->
      {entries, more?, top} = read(source, fleet_id, position, limit, read_as)
      entries = if more?, do: Enum.drop(entries, -1), else: entries
      %{entries: entries, more?: more?, position: position || top, reads: reads + 1}
    end

    streams = Map.new(sources, &{&1, fetch.(&1, positions[&1], 0)})
    {taken, streams} = merge(streams, limit, [], fetch)

    %{items: name(taken, fleet_id, read_as[:actor]), cursor: next_cursor(streams)}
  end

  @doc """
  The wallet each `:transfer` among `items` moved its key to, by the item's
  id. The items name no wallet; a page that shows a run of transfers to one
  wallet as one line reads them here.
  """
  @spec receivers(String.t(), [item()]) :: %{String.t() => String.t()}
  def receivers(fleet_id, items) do
    case for %{kind: :transfer, id: "transfer:" <> seq} <- items, do: String.to_integer(seq) do
      [] ->
        %{}

      seqs ->
        fleet_id
        |> Keys.epochs_by_record_seq!(seqs)
        |> Map.new(&{"transfer:#{&1.record_seq}", &1.owner_wallet})
    end
  end

  # The workspace's changes are read only by whoever reads the workspace.
  defp sources(fleet_id, read_as) do
    class =
      get_in(read_as, [:context, :shared, :access, :class]) ||
        Access.class(read_as[:actor], fleet_id)

    if Access.enough?(class, :read, :workspace), do: @sources, else: @sources -- [:graph]
  end

  # Where a walk begins in each source. Posts are read up to now by the
  # database's clock, which stamps them, one microsecond past so that the time
  # itself is included. The sources kept in record order begin just past the
  # newest record their first read finds.
  defp start do
    %Postgrex.Result{rows: [[written]]} = Repo.query!("SELECT clock_timestamp()")

    %{
      posts: {DateTime.add(written, 1, :microsecond), nil},
      graph: nil,
      keys: nil,
      shards: nil,
      proposals: nil
    }
  end

  @doc """
  The item a fleet features at `now`, as anyone reads it: the latest
  proposal carried out, if in the last seven days. Nil otherwise, and the
  fleet's latest item, the first of `page/3`, is featured instead; the caller
  has read it already.
  """
  @spec headline(String.t(), DateTime.t()) :: item() | nil
  def headline(fleet_id, %DateTime{} = now) do
    execution = last_execution(fleet_id)

    if execution && not DateTime.before?(execution.at, DateTime.add(now, -@recent, :second)),
      do: hd(name([execution], fleet_id, nil))
  end

  defp last_execution(fleet_id) do
    fleet_id
    |> Proposals.executions_recorded_before!(nil, 1)
    |> Enum.map(&execution_entry/1)
    |> List.first()
  end

  # Merging: the newest head among the sources goes next, until the page is
  # full or every source is done. A source that has handed over all it read
  # and has more is read again first, since its next item could be newer than
  # any other; each read hands over at least one entry. A source already
  # read as often as a page allows ends the page there.
  defp merge(streams, 0, taken, _fetch), do: {Enum.reverse(taken), streams}

  defp merge(streams, left, taken, fetch) do
    case Enum.find(order(streams), &(streams[&1].entries == [] and streams[&1].more?)) do
      nil ->
        take(streams, left, taken, fetch)

      dry ->
        case streams[dry] do
          %{reads: @reads_per_page} ->
            {Enum.reverse(taken), streams}

          %{position: position, reads: reads} ->
            merge(Map.put(streams, dry, fetch.(dry, position, reads)), left, taken, fetch)
        end
    end
  end

  defp take(streams, left, taken, fetch) do
    case next_source(streams) do
      nil ->
        {Enum.reverse(taken), streams}

      source ->
        %{entries: [entry | rest]} = stream = Map.fetch!(streams, source)
        stream = %{stream | entries: rest, position: entry.position}
        merge(Map.put(streams, source, stream), left - 1, [entry | taken], fetch)
    end
  end

  defp next_source(streams) do
    streams
    |> order()
    |> Enum.with_index()
    |> Enum.filter(fn {source, _rank} -> streams[source].entries != [] end)
    |> Enum.max_by(fn {source, rank} -> {stamp(hd(streams[source].entries).at), -rank} end, fn ->
      nil
    end)
    |> case do
      nil -> nil
      {source, _rank} -> source
    end
  end

  # The sources read, in their fixed order.
  defp order(streams), do: Enum.filter(@sources, &Map.has_key?(streams, &1))

  defp next_cursor(streams) do
    if Enum.all?(streams, fn {_source, s} -> s.entries == [] and not s.more? end),
      do: nil,
      else: Map.new(streams, fn {source, s} -> {source, s.position} end)
  end

  defp stamp(at), do: DateTime.to_unix(at, :microsecond)

  # Reading: each source answers its entries newest first, whether it has
  # more beyond them, and, for a source kept in record order, the place just
  # past the newest record read, where a walk begins. Each entry carries the
  # place in its source just past it.
  defp read(:posts, fleet_id, {at, id}, _limit, read_as) do
    lines = Rooms.fleet_lines_before!(fleet_id, at, id, @posts_read, read_as)
    {group_lines(lines), length(lines) == @posts_read, nil}
  end

  defp read(:graph, fleet_id, seq, _limit, _read_as) do
    events = Graph.notable_before!(fleet_id, seq, @graph_read)

    {events |> Enum.map(&graph_entry/1) |> group_work(), length(events) == @graph_read,
     top(events, :seq)}
  end

  defp read(:keys, fleet_id, seq, _limit, _read_as) do
    epochs = Keys.epochs_recorded_before!(fleet_id, seq, @keys_read)
    first = if Presets.given?(fleet_id), do: :given, else: :sale
    {group_epochs(epochs, first), length(epochs) == @keys_read, top(epochs, :record_seq)}
  end

  defp read(:shards, fleet_id, seq, limit, _read_as) do
    events = Keys.shard_events_recorded_before!(fleet_id, seq, limit + 1, load: [:agent_profile])
    {Enum.map(events, &shard_entry/1), length(events) > limit, top(events, :record_seq)}
  end

  defp read(:proposals, fleet_id, seq, limit, _read_as) do
    reads = [
      {Proposals.proposals_recorded_before!(fleet_id, seq, limit + 1), limit + 1},
      {Proposals.votes_recorded_before!(fleet_id, seq, @votes_read,
         load: [proposal: [:yes_keys, :no_keys, :abstain_keys]]
       ), @votes_read},
      {Proposals.executions_recorded_before!(fleet_id, seq, limit + 1), limit + 1}
    ]

    # Each kind of record is read to its own depth. Below the shallowest
    # full read's last record, a record of that kind may be missing, so the
    # records are merged only down to there.
    floor =
      reads
      |> Enum.filter(fn {records, wanted} -> length(records) == wanted end)
      |> Enum.map(fn {records, _wanted} -> List.last(records).record_seq end)
      |> Enum.max(fn -> 0 end)

    records = reads |> Enum.flat_map(&elem(&1, 0)) |> Enum.sort_by(& &1.record_seq, :desc)
    complete = Enum.filter(records, &(&1.record_seq >= floor))

    {group_records(complete), floor > 0, top(records, :record_seq)}
  end

  defp shard_entry(%{kind: :issued} = event),
    do:
      entry("shard:#{event.record_seq}", event.observed_at, :shard_issued, event.record_seq, %{
        token_id: event.token_id,
        wallet: event.wallet,
        agent: event.agent_profile && agent(event.agent_profile),
        expires_at: event.expires_at
      })

  defp shard_entry(%{kind: :ended} = event),
    do:
      entry("shard:#{event.record_seq}", event.observed_at, :shard_ended, event.record_seq, %{
        token_id: event.token_id,
        wallet: event.wallet,
        agent: event.agent_profile && agent(event.agent_profile),
        stepped_down?: event.ended_by == event.wallet
      })

  defp top([], _field), do: 1
  defp top([newest | _], field), do: Map.fetch!(newest, field) + 1

  defp entry(id, at, kind, position, facts),
    do: %{id: id, at: at, kind: kind, position: position, facts: facts}

  # A run: from the head of `rest`, the entries `joins?` lets follow
  # `first`, each at most an hour before the one after it, six hours at most
  # from `first` and fifty in all, by the time `at` gives. The run comes
  # newest first, `first` at its head.
  defp take_run(rest, first, joins?, at), do: take_run(rest, first, [first], joins?, at)

  defp take_run([next | rest], first, [last | _] = run, joins?, at) do
    if joins?.(next) and length(run) < @group_cap and
         DateTime.diff(at.(last), at.(next), :microsecond) <= @post_gap and
         DateTime.diff(at.(first), at.(next), :microsecond) <= @post_span,
       do: take_run(rest, first, [next | run], joins?, at),
       else: {Enum.reverse(run), [next | rest]}
  end

  defp take_run([], _first, run, _joins?, _at), do: {Enum.reverse(run), []}

  # Posts: a run of posts in one room is one item.
  defp group_lines([]), do: []

  defp group_lines([%{kind: :room_named} = line | rest]) do
    item =
      entry("room_named:#{line.id}", line.inserted_at, :room_named, line_position(line), %{
        room: room(line.room),
        by: author(line),
        topic: line.excerpt
      })

    [item | group_lines(rest)]
  end

  defp group_lines([first | rest]) do
    {run, rest} =
      take_run(rest, first, &(&1.kind == :post and &1.room_id == first.room_id), & &1.inserted_at)

    [posts_entry(run) | group_lines(rest)]
  end

  defp posts_entry([newest] = _run) do
    entry("posts:#{newest.id}", newest.inserted_at, :post, line_position(newest), %{
      room: room(newest.room),
      by: author(newest),
      excerpt: newest.excerpt
    })
  end

  defp posts_entry([newest | _] = run) do
    keys = run |> Enum.map(&author/1) |> Enum.uniq_by(&(&1.token_id || &1.wallet))

    entry("posts:#{newest.id}", newest.inserted_at, :posts, line_position(List.last(run)), %{
      room: room(newest.room),
      count: length(run),
      keys: Enum.take(keys, @listed_keys),
      others: max(length(keys) - @listed_keys, 0),
      excerpt: newest.excerpt
    })
  end

  defp line_position(line), do: {line.inserted_at, line.id}

  defp room(room), do: %{slug: room.slug, name: room.name, topic: room.topic}

  # The key a line was written as, or the wallet of someone who wrote as no key.
  defp author(line),
    do: %{
      token_id: line.as_key,
      agent: line.agent_profile && line.agent_profile.name,
      wallet: line.author_wallet
    }

  # Keys: a run of first owners, from one purchase or several, is one item of
  # `kind`: `:sale`, or `:given` where the fleet's Keys are given. The item is
  # named for its earliest Key.
  defp group_epochs([], _kind), do: []

  defp group_epochs([%{ownership_epoch: 1} = first | rest], kind) do
    {sold, rest} = take_run(rest, first, &(&1.ownership_epoch == 1), & &1.observed_at)
    last = List.last(sold)

    item =
      entry("#{kind}:#{last.record_seq}", first.observed_at, kind, last.record_seq, %{
        token_ids: sold |> Enum.map(& &1.token_id) |> Enum.sort()
      })

    [item | group_epochs(rest, kind)]
  end

  defp group_epochs([epoch | rest], kind) do
    item =
      entry("transfer:#{epoch.record_seq}", epoch.observed_at, :transfer, epoch.record_seq, %{
        token_id: epoch.token_id
      })

    [item | group_epochs(rest, kind)]
  end

  # Proposal records: consecutive votes on one proposal are one item, fifty
  # votes at most.
  defp group_records([]), do: []

  defp group_records([%Proposals.Vote{} = first | _] = records) do
    {votes, rest} =
      records
      |> Enum.take(@group_cap)
      |> Enum.split_while(
        &match?(%Proposals.Vote{proposal_id: id} when id == first.proposal_id, &1)
      )

    rest = rest ++ Enum.drop(records, @group_cap)
    sides = Enum.group_by(votes, & &1.choice)

    item =
      entry(
        "votes:#{first.record_seq}",
        first.observed_at,
        :votes,
        List.last(votes).record_seq,
        %{
          number: first.proposal_number,
          yes: tally(sides[:yes]),
          no: tally(sides[:no]),
          abstain: tally(sides[:abstain]),
          totals: %{
            yes: first.proposal.yes_keys,
            no: first.proposal.no_keys,
            abstain: first.proposal.abstain_keys
          }
        }
      )

    [item | group_records(rest)]
  end

  defp group_records([%Proposals.Proposal{} = proposal | rest]) do
    item =
      entry(
        "proposal:#{proposal.record_seq}",
        proposal.observed_at,
        :proposed,
        proposal.record_seq,
        %{
          number: proposal.number,
          proposer: {:holder, proposal.proposer},
          calls: length(proposal.calls)
        }
      )

    [item | group_records(rest)]
  end

  defp group_records([%Proposals.Execution{} = execution | rest]),
    do: [execution_entry(execution) | group_records(rest)]

  defp execution_entry(execution) do
    entry(
      "executed:#{execution.record_seq}",
      execution.observed_at,
      :executed,
      execution.record_seq,
      %{number: execution.proposal_number}
    )
  end

  defp tally(nil), do: tally([])

  defp tally(votes) do
    token_ids = votes |> Enum.flat_map(& &1.token_ids) |> Enum.uniq() |> Enum.sort()
    %{count: length(token_ids), token_ids: Enum.take(token_ids, @listed_keys)}
  end

  # Workspace changes: a run of tasks one key added is one item, and so is a
  # run of one change one key made to items of one type.
  defp group_work([]), do: []

  defp group_work([first | rest]) do
    cond do
      adding_task?(first, first.facts.by) ->
        {run, rest} = take_run(rest, first, &adding_task?(&1, first.facts.by), & &1.at)
        [tasks_entry(run) | group_work(rest)]

      first.kind in @repeated ->
        {run, rest} = take_run(rest, first, &same_change?(&1, first), & &1.at)
        [changes_entry(run) | group_work(rest)]

      true ->
        [first | group_work(rest)]
    end
  end

  defp same_change?(entry, first),
    do:
      entry.kind == first.kind and entry.facts.by == first.facts.by and type(entry) == type(first)

  # Every item's id starts with its type, as in "task#4".
  defp type(%{facts: %{item: {:item, id}}}), do: id |> String.split("#") |> hd()

  defp changes_entry([only]), do: only

  defp changes_entry([newest | _] = run) do
    entry("changes:#{newest.position}", newest.at, :changes, List.last(run).position, %{
      by: newest.facts.by,
      change: newest.kind,
      type: type(newest),
      count: length(run)
    })
  end

  # A task `by` added.
  defp adding_task?(%{kind: :created, facts: %{by: by, item: {:item, "task#" <> _}}}, by),
    do: by != nil

  defp adding_task?(_entry, _by), do: false

  defp tasks_entry([only]), do: only

  defp tasks_entry([newest | _] = run) do
    entry("tasks:#{newest.position}", newest.at, :tasks, List.last(run).position, %{
      by: newest.facts.by,
      added: length(run)
    })
  end

  defp graph_entry(event) do
    {kind, facts} = change(event.type, event.brief)

    entry(
      "graph:#{event.seq}",
      at(event.timestamp),
      kind,
      event.seq,
      Map.put(facts, :by, actor(event.actor))
    )
  end

  defp change("object.created", %{"object_type" => "review"} = brief),
    do: {:reviewed, %{item: {:item, brief["task"]}, decision: brief["decision"]}}

  defp change("object.created", brief), do: {:created, %{item: {:item, brief["object"]}}}

  defp change("relation.created", brief) do
    {:linked,
     %{
       relation: brief["relation_type"],
       source: {:item, brief["source"]},
       target: {:item, brief["target"]}
     }}
  end

  defp change("patch.applied", %{"object" => id} = brief) do
    values = brief["values"]
    item = %{item: {:item, id}}

    cond do
      brief["archived"] ->
        {:archived, item}

      brief["submitted"] ->
        {:submitted, item}

      brief["joins"] > 0 ->
        {:joined, item}

      brief["joins"] < 0 ->
        {:left, item}

      match?(%{"progress" => %{"new" => _}}, values) ->
        {:progress, Map.put(item, :progress, values["progress"]["new"])}

      match?(%{"status" => %{"new" => _}}, values) ->
        {:status, Map.put(item, :status, values["status"]["new"])}

      true ->
        {:revised, item}
    end
  end

  # A member writes as its key; the workspace's own actors write as
  # `keyfleet:<part>`. Any other actor is not one the workspace records.
  defp actor("keyfleet:" <> _part), do: nil

  defp actor(actor) do
    case Graph.Event.member(actor) do
      {token_id, "agent", wallet} -> {:actor, token_id, wallet}
      {token_id, "human", _wallet} -> %{token_id: token_id, agent: nil}
    end
  end

  # The log stamps every event in UTC.
  defp at(timestamp) do
    {:ok, at, _offset} = DateTime.from_iso8601(timestamp)
    at
  end

  defp agent(profile), do: %{id: profile.id, name: profile.name}

  # Naming: the facts hold references (`{:actor, token_id, wallet}`,
  # `{:holder, wallet}` and `{:item, id}`), looked up
  # together for the whole page, a batch per kind of reference, items as
  # `actor` may read their titles.
  defp name([], _fleet_id, _actor), do: []

  defp name(entries, fleet_id, actor) do
    refs = entries |> Enum.flat_map(&refs(&1.facts)) |> Enum.group_by(&elem(&1, 0))
    names = lookup(refs, fleet_id, actor)

    Enum.map(entries, fn entry ->
      %{id: entry.id, at: entry.at, kind: entry.kind, facts: resolve(entry.facts, names)}
    end)
  end

  defp refs(facts) when is_map(facts) and not is_struct(facts),
    do: facts |> Map.values() |> Enum.flat_map(&refs/1)

  defp refs(values) when is_list(values), do: Enum.flat_map(values, &refs/1)

  defp refs(ref)
       when is_tuple(ref) and
              elem(ref, 0) in [:actor, :holder, :item],
       do: [ref]

  defp refs(_value), do: []

  defp lookup(refs, fleet_id, actor) do
    %{
      actor: agents_by_wallet(refs[:actor]),
      holder: holders(fleet_id, refs[:holder]),
      item: items(fleet_id, refs[:item], actor)
    }
  end

  defp agents_by_wallet(nil), do: %{}

  defp agents_by_wallet(refs), do: refs |> Enum.map(&elem(&1, 2)) |> Agents.names_by_wallet()

  defp holders(_fleet_id, nil), do: %{}

  defp holders(fleet_id, refs) do
    wallets = refs |> Enum.map(&elem(&1, 1)) |> Enum.uniq()

    fleet_id
    |> Keys.lowest_keys_held!(wallets)
    |> Map.new(&{&1.owner_wallet, &1.token_id})
  end

  defp items(_fleet_id, nil, _actor), do: %{}

  # An item `actor` may not read the title of is not among those read.
  defp items(fleet_id, refs, actor) do
    ids = refs |> Enum.map(&elem(&1, 1)) |> Enum.uniq()

    fleet_id
    |> Graph.object_titles!(ids, load: [:card], actor: actor)
    |> Map.new(&{&1.id, &1})
  end

  defp resolve(facts, names) when is_map(facts) and not is_struct(facts),
    do: Map.new(facts, fn {key, value} -> {key, resolve(value, names)} end)

  defp resolve(values, names) when is_list(values), do: Enum.map(values, &resolve(&1, names))

  defp resolve({:actor, token_id, wallet}, names),
    do: %{token_id: token_id, agent: names.actor[wallet]}

  defp resolve({:holder, wallet}, names), do: %{wallet: wallet, token_id: names.holder[wallet]}

  defp resolve({:item, id}, names) do
    type = id |> String.split("#", parts: 2) |> hd()

    case names.item[id] do
      nil -> %{id: id, type: type, title: nil}
      %{type: "finding"} = object -> finding(object)
      object -> %{id: id, type: object.type, title: object.title}
    end
  end

  defp resolve(value, _names), do: value

  defp finding(object),
    do: %{
      id: object.id,
      type: "finding",
      title: object.title,
      confidence: object.card["confidence"]
    }
end
