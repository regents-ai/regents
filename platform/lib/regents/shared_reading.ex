defmodule Regents.SharedReading do
  @moduledoc """
  A figure every reader it admits sees alike, read once and shared by every open
  page. Ported from ash-template's `AshTemplate.SharedReading`.

  It is for a reading built from many rows, such as the Points board. Anything
  that differs by viewer is reread under that viewer's scope and does not belong
  here.

  One producer owns each key and calls `put/2` when it has a reading, or
  `degraded/1` when it could not get one. A page calls `subscribe/1`, then
  `fetch/1`, and on each `{:shared_reading, key}` it fetches again. Pages are
  woken only when the reading or its `degraded?` mark differs from the one held;
  `at`, the moment it was last read, moves without waking anyone. A wake-up
  reaches this machine's pages only, because each machine keeps its own table and
  runs its own producers.

  A reading never disables or delays an on-chain button.

  ## Kinds

  A key is `{kind, id}`. `kind` is one of `@kinds` and `id` is an integer or a
  short string the site already holds in its own rows or settings, never text
  from a request. Each kind states who may see it and why, the most keys it may
  hold and the largest reading it accepts, so adding one is a reviewed change. A
  reading is small plain data: numbers, strings, atoms, dates, `Decimal`s, and
  maps, lists or tuples of them. An Ash record or any other struct is refused, as
  is a reading over its kind's size.

  A producer that rereads on notice does so when `heal/1` asks, each minute
  (`Regents.SharedReading.Heal`), which is also what mends a notice that was lost.

  ## Measurements

  Every reading offered to `put/2` reports its `bytes` and its kind's `limit`
  (`[:regents, :shared_reading, :size]`), exported as
  `health.shared_reading.size.percent`, so a reading growing towards its limit
  shows before it is refused.
  """

  use GenServer

  @table __MODULE__
  @producers :regents_shared_reading_producers
  @load_timeout 15_000

  # audience: who may see it, and why. keys: the most this kind holds.
  # bytes: the largest reading, measured as `:erlang.external_size/1`.
  @kinds %{
    # Ten rows, however many accounts have points: with a 1 KB name, a 2.3 KB
    # square pattern, a 1 KB picture address and an ENS name each, ten rows
    # measure about 48 KB.
    points_board: %{
      audience:
        "signed-in people and paired agents, the readers the Points page and the agent's " <>
          "Points answer admit; each gets the rows without account ids " <>
          "(Regents.Account.Points.Board)",
      keys: 1,
      bytes: 65_536
    },
    keyfleet_season_coins: %{
      audience:
        "every visitor: which Coinbase products a season's pick may name is read from " <>
          "Coinbase's own public list of products, which anyone may read " <>
          "(Regents.Keyfleet.Seasons.CoinList)",
      keys: 1,
      # One id of at most 14 characters for each of the 406 products quoted in
      # US dollars on 18 Nov 2026, were every one of them open to picks, is
      # about 10 KB.
      bytes: 16_384
    },
    keyfleet_fleet_agents: %{
      audience:
        "every visitor: the agents here and what their check-ins say are open to a signed-out read " <>
          "(Regents.Keyfleet.Agents.AgentProfile :here_in_fleet, Regents.Keyfleet.Agents.CheckIn read policy) " <>
          "and in the open fleet directory; if either policy tightens, this kind changes with it. " <>
          "Its two holder counts are numbers only: how many addresses hold a Key, which the " <>
          "chain shows anyone, and how many of them acted in the last hour, naming nobody. " <>
          "Its faces name the holder of each of the agents' Keys, the Key they write as and " <>
          "how many Keys they hold (Regents.Keyfleet.Keys.faces/2): the chain shows who holds each Key, " <>
          "every address an account links is public as the Member List shows, and the Key a " <>
          "person writes as shows beside everything they write",
      # One for each fleet in Regents.Keyfleet.Fleets' catalog: a sixth fleet raises
      # it, or its Here now is refused and shown as not counted.
      keys: 5,
      # 26,881 bytes measured at its fullest before faces, which add about
      # 120 bytes for each of up to 50 Keys; the rest leaves room for a longer
      # picture address in production.
      bytes: 40_960
    },
    keyfleet_key_agents: %{
      audience:
        "every visitor: a Key's active shards and their agents are open to a signed-out read " <>
          "(Regents.Keyfleet.Keys.ShardEvent and Regents.Keyfleet.Agents.CheckIn read policies); " <>
          "if either policy tightens, this kind changes with it",
      keys: 10_000,
      bytes: 20_480
    },
    keyfleet_fleet_now: %{
      audience:
        "every visitor: a fleet's activity, what it is working on and how far it has sold, as a signed-out " <>
          "visitor reads them, are open to a signed-out read: Regents.Keyfleet.Activity.page/3 and " <>
          "headline/2 with no actor (the Public room and the Keys' threads, under the " <>
          "Regents.Keyfleet.Rooms.Message read policy, and no workspace changes), " <>
          "Regents.Keyfleet.Graph.shown/1 (the :titles read of projects and :open_goals), the fleet's " <>
          "record, and the Keys sold " <>
          "(Regents.Keyfleet.Chain.minted/2), which the chain shows anyone, and the holders of the Keys " <>
          "in its activity with the Key each writes as (Regents.Keyfleet.Keys.faces/2), as open as the " <>
          "Member List and what they write, and the first page of its Public place as a " <>
          "signed-out visitor reads it (RegentsWeb.Keyfleet.WorkspacePage.board/3 with no actor: " <>
          "Regents.Keyfleet.Projects.Publication :in_fleet, which anyone reads, and what each Key chose " <>
          "to show); if any of these tightens, this kind changes with it",
      # One for each fleet in Regents.Keyfleet.Fleets' catalog, like keyfleet_fleet_agents.
      keys: 5,
      # Not yet measured at its fullest: a page of 30 activity items, the
      # projects and their open goals, eight things made public, each title
      # at most 64 characters, and a few numbers. A reading over it is refused
      # and counted, and pages keep the one before.
      bytes: 65_536
    },
    keyfleet_fleet_proposals: %{
      audience:
        "every visitor: the first page of a fleet's proposals, their tallies and words, is open to a signed-out " <>
          "read (Regents.Keyfleet.Proposals.Proposal, Vote, Cancellation, Execution and Words read " <>
          "policies), with the fleet's record, its chain cursor (Regents.Keyfleet.Chain.Cursor) and the " <>
          "tokens its treasury pays in (Regents.Keyfleet.Treasury.AssetDetails and Reading read " <>
          "policies); if any of these tightens, this kind changes with it",
      # One for each fleet in Regents.Keyfleet.Fleets' catalog, like keyfleet_fleet_agents.
      keys: 5,
      # Not yet measured: twenty proposals, each with up to 4,000 bytes of words.
      bytes: 131_072
    },
    keyfleet_fleet_treasury: %{
      audience:
        "every visitor: a fleet's Treasury page is open to a signed-out read: its latest reading, money " <>
          "history and advances (Regents.Keyfleet.Treasury.Reading, Event and AssetDetails read " <>
          "policies), the votes carried out (Regents.Keyfleet.Proposals.Proposal and Execution), the " <>
          "fleet's record, its chain cursor and the Keys sold (Regents.Keyfleet.Keys.KeyAttachment), " <>
          "which the chain shows anyone, and its usage this month (Regents.Keyfleet.Usage.Month read " <>
          "policy); if any of these tightens, this kind changes with it",
      keys: 5,
      # Not yet measured: the latest history, the open advances and five votes carried out.
      bytes: 65_536
    },
    keyfleet_share_card: %{
      audience:
        "every visitor: the figures on a fleet's share picture are open to a signed-out read: its Keys sold " <>
          "(Regents.Keyfleet.Chain.minted/2) and the Key to change hands last " <>
          "(Regents.Keyfleet.Keys.KeyAttachment), which the chain shows anyone, its treasury's latest " <>
          "reading (Regents.Keyfleet.Treasury.Reading read policy), and that Key's name and card " <>
          "picture (Regents.Keyfleet.Keys.KeyReveal and KeyPicture read policies), which its Key's " <>
          "page shows anyone; if any of these tightens, this kind changes with it",
      # One for each fleet with a picture of its own (RegentsWeb.Keyfleet.ShareCard.fleets/0).
      keys: 2,
      # A few short lines: the Keys, up to three treasury amounts, a Key's name
      # and an IPFS address.
      bytes: 1_024
    },
    keyfleet_project_cards: %{
      audience:
        "every visitor: what a project's share picture shows is open to a signed-out read: the " <>
          "project's name and title and the Key holding it (Regents.Keyfleet.Projects.Project :titles " <>
          "policy), which its page shows anyone, and that Key's name and card picture " <>
          "(Regents.Keyfleet.Keys.KeyReveal and KeyPicture read policies), which its Key's page shows " <>
          "anyone; if any of these tightens, this kind changes with it",
      # One for each project, deleted ones aside, of the fleets with a picture
      # of their own (RegentsWeb.Keyfleet.ShareCard.fleets/0), and one more for each of
      # those fleets holding how many it has. A Key holds at most one active
      # project and five archived ones, and three projects no Key holds
      # (Regents.Keyfleet.Projects), so 6 x (1,024 + 1,998) + 3 + 2 = 18,137 at the
      # most. A project past the count shows its fleet's picture.
      keys: 18_200,
      # About 200 bytes: a title of up to 60 characters, a Key's name and an
      # IPFS address. A larger one is refused; the one held before stays, and
      # with none its project's page shows the fleet's picture.
      bytes: 1_024
    },
    keyfleet_proposal: %{
      audience:
        "every visitor: a proposal's first page is open to a signed-out read: the proposal, its calls, its " <>
          "first fifty votes and its words (Regents.Keyfleet.Proposals.Proposal, Vote, Cancellation, " <>
          "Execution and Words read policies), what its calls come to at the treasury's latest " <>
          "balance (Regents.Keyfleet.Treasury.Reading and AssetDetails) and where it stands on the vote " <>
          "contract, which the chain shows anyone; if any of these tightens, this kind changes " <>
          "with it",
      # Twenty for each catalog fleet, with room for a pass to put new proposals
      # before it deletes the ones they pushed off the list.
      keys: 200,
      # Up to 4,000 bytes of words, fifty votes and the calls; a larger one is
      # refused, counted, and read for each visit instead.
      bytes: 131_072
    },
    # `Regents.Patchbay.WalletBench.Board`'s keys: the board as most visits see it,
    # How the bench works, for a visit with filters the bench's rows and each
    # of the five tests' checks, what every pair's page and the sitemap share,
    # and one for each agent and wallet pair on the roster.
    wallet_bench: %{
      audience:
        "every visitor: Techtree publishes the bench for anyone to read " <>
          "(Regents.Patchbay.WalletBench's resources, read policy authorize_if always()); " <>
          "every visitor sees the same board",
      keys: 400,
      bytes: 48_000_000
    },
    # `Regents.Patchbay.Forum.HiddenSites`'s one key: the listed hosts and domains a
    # check found no tools on.
    hidden_sites: %{
      audience:
        "every visitor: site checks are public (Regents.Patchbay.Forum.SiteCheck's read policy " <>
          "authorize_if always()); every visitor sees the same listing",
      keys: 1,
      bytes: 2_000_000
    },
    # One for each Autolaunch auction deployment (`Regents.Autolaunch.ChainHead`):
    # "base", "stocks" and "robinhood".
    chain_head: %{
      audience: "every visitor: a chain's newest block number is public on the chain itself",
      keys: 3,
      bytes: 64
    },
    # How many launches each Base launchpad has made (`Regents.Autolaunch.LaunchDiscovery.Count`).
    launch_count: %{
      audience:
        "every visitor: a launchpad's launch count is public on Base, and the site's count " <>
          "says only how far its lists have got",
      keys: 2,
      bytes: 128
    },
    # The last 30 days of each covered-call market's reference price
    # (`Regents.Autolaunch.CoveredCalls.PriceLine`), by the market's symbol.
    price_history: %{
      audience: "every visitor: a Chainlink feed's past prices are public on the chain itself",
      keys: 4,
      bytes: 8_192
    }
  }

  @type key :: {kind :: atom(), id :: integer() | String.t()}
  @type entry :: %{reading: term(), at: DateTime.t() | nil, degraded?: boolean()}

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc "The reading held for `key`, or `:error` while there is none."
  @spec fetch(key()) :: {:ok, entry()} | :error
  def fetch({kind, id} = key)
      when is_map_key(@kinds, kind) and (is_integer(id) or is_binary(id)) do
    case :ets.lookup(@table, key) do
      [{^key, entry}] ->
        {:ok, entry}

      [] ->
        case maybe_load(key) do
          :loaded -> lookup(key)
          :miss -> :error
        end
    end
  rescue
    # No table for the instant its owner restarts: the same as no reading.
    ArgumentError -> :error
  end

  @doc """
  Registers a lazy producer for `kind` or a specific `key` so cold reads wake
  the producer on first demand instead of querying at boot. `mode` is `:sync`
  (DB-backed readers that answer `:ensure_loaded`) or `:async` (chain/HTTP
  readers that answer `:wake` casts and push via PubSub).
  """
  @spec register_producer(atom() | key(), GenServer.server(), :sync | :async) :: :ok
  def register_producer(target, server, mode \\ :sync) when mode in [:sync, :async] do
    :ets.insert(@producers, {producer_target(target), server, mode, false})
    :ok
  rescue
    ArgumentError -> :ok
  end

  @doc "Records whether the lazy producer for `target` has loaded its readings."
  @spec mark_loaded(atom() | key(), boolean()) :: :ok
  def mark_loaded(target, loaded?) when is_boolean(loaded?) do
    id = producer_target(target)

    case :ets.lookup(@producers, id) do
      [{^id, server, mode, _was}] ->
        :ets.insert(@producers, {id, server, mode, loaded?})
        :ok

      [] ->
        :ok
    end
  rescue
    ArgumentError -> :ok
  end

  @doc "Deletes every key held for `kind` (for example, when its product goes idle)."
  @spec clear_kind(atom()) :: :ok
  def clear_kind(kind) when is_map_key(@kinds, kind) do
    Enum.each(ids(kind), &delete({kind, &1}))
    :ok
  end

  @doc """
  The id of every key held for `kind`. For a kind's own producer on its pass
  only, never a page's mount or each event, since it walks the whole table;
  never count with it.
  """
  @spec ids(atom()) :: [integer() | String.t()]
  def ids(kind) when is_map_key(@kinds, kind) do
    :ets.select(@table, [{{{kind, :"$1"}, :_}, [], [:"$1"]}])
  rescue
    # No table for the instant its owner restarts: the same as no keys.
    ArgumentError -> []
  end

  @doc "Hear `{:shared_reading, key}` whenever the reading for `key` changes."
  @spec subscribe(key()) :: :ok
  def subscribe(key), do: Phoenix.PubSub.subscribe(Regents.PubSub, topic(checked(key)))

  @doc "Stops hearing `key`, for a page that stays open and no longer shows it."
  @spec unsubscribe(key()) :: :ok
  def unsubscribe(key), do: Phoenix.PubSub.unsubscribe(Regents.PubSub, topic(checked(key)))

  @doc """
  Stores `reading` as read just now. Answers `{:error, :too_large}`,
  `{:error, :not_plain}` or `{:error, :too_many_keys}` when it is refused; the
  reading held before then stays.
  """
  @spec put(key(), term()) :: :ok | {:error, :too_large | :not_plain | :too_many_keys}
  def put(key, reading) do
    {kind, _id} = checked(key)

    # Checked here, in the producer, so a reading that cannot be checked fails
    # its producer and never the table's owner.
    with :ok <- fits(kind, reading) do
      GenServer.call(__MODULE__, {:put, key, reading})
    end
  end

  @doc """
  Marks `key` as not read this time. The last reading stays, marked `degraded?`;
  a key that never had one holds `reading: nil`.
  """
  @spec degraded(key()) :: :ok | {:error, :too_many_keys}
  def degraded(key), do: GenServer.call(__MODULE__, {:degraded, checked(key)})

  @doc """
  Asks the producer of `kind`, on every machine, to read all its keys again.
  The producer hears `{:shared_reading_heal, kind}` after `subscribe_heal/1`.
  """
  @spec heal(atom()) :: :ok
  def heal(kind) when is_map_key(@kinds, kind) do
    Phoenix.PubSub.broadcast(Regents.PubSub, heal_topic(kind), {:shared_reading_heal, kind})
  end

  @spec subscribe_heal(atom()) :: :ok
  def subscribe_heal(kind) when is_map_key(@kinds, kind),
    do: Phoenix.PubSub.subscribe(Regents.PubSub, heal_topic(kind))

  @doc "Forgets `key`, when the row or setting it stood for has ended."
  @spec delete(key()) :: :ok
  def delete(key), do: GenServer.call(__MODULE__, {:delete, checked(key)})

  @impl true
  def init(nil) do
    :ets.new(@table, [:named_table, :protected, read_concurrency: true])
    :ets.new(@producers, [:named_table, :public, read_concurrency: true, write_concurrency: true])
    {:ok, nil}
  end

  @impl true
  def handle_call({:put, key, reading}, _from, state) do
    held = held(key)

    reply =
      with :ok <- room(key, held),
           do: store(key, held, %{reading: reading, at: DateTime.utc_now(), degraded?: false})

    {:reply, reply, state}
  end

  def handle_call({:degraded, key}, _from, state) do
    held = held(key)

    reply =
      with :ok <- room(key, held),
           do: store(key, held, Map.put(held || %{reading: nil, at: nil}, :degraded?, true))

    {:reply, reply, state}
  end

  def handle_call({:delete, key}, _from, state) do
    if :ets.member(@table, key) do
      :ets.delete(@table, key)
      wake(key)
    end

    {:reply, :ok, state}
  end

  defp held(key) do
    case :ets.lookup(@table, key) do
      [{^key, entry}] -> entry
      [] -> nil
    end
  end

  # Stored first, so a page woken by it reads the new entry.
  defp store(key, held, entry) do
    :ets.insert(@table, {key, entry})
    if changed?(held, entry), do: wake(key)
    :ok
  end

  defp changed?(nil, _entry), do: true

  defp changed?(held, entry),
    do: held.reading != entry.reading or held.degraded? != entry.degraded?

  defp wake(key),
    do: Phoenix.PubSub.local_broadcast(Regents.PubSub, topic(key), {:shared_reading, key})

  defp topic({kind, id}), do: "shared_reading:#{kind}:#{id}"
  defp heal_topic(kind), do: "shared_reading_heal:#{kind}"

  # Every offered reading's size is reported against its kind's limit, so one
  # that grows shows nearing the limit well before it is refused.
  defp fits(kind, reading) do
    bytes = :erlang.external_size(reading)
    limit = @kinds[kind].bytes

    :telemetry.execute(
      [:regents, :shared_reading, :size],
      %{bytes: bytes, limit: limit},
      %{kind: kind}
    )

    cond do
      bytes > limit -> {:error, :too_large}
      not plain?(reading) -> {:error, :not_plain}
      true -> :ok
    end
  end

  defp room(_key, %{}), do: :ok

  defp room({kind, _id}, nil) do
    if :ets.select_count(@table, [{{{kind, :_}, :_}, [], [true]}]) < @kinds[kind].keys,
      do: :ok,
      else: {:error, :too_many_keys}
  end

  defp plain?(%module{}), do: module in [DateTime, Date, Decimal]

  defp plain?(map) when is_map(map),
    do: Enum.all?(map, fn {key, value} -> plain?(key) and plain?(value) end)

  defp plain?([]), do: true
  defp plain?([head | tail]), do: plain?(head) and plain?(tail)
  defp plain?(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> plain?()
  defp plain?(term), do: is_number(term) or is_binary(term) or is_atom(term)

  defp lookup(key) do
    case :ets.lookup(@table, key) do
      [{^key, entry}] -> {:ok, entry}
      [] -> :error
    end
  rescue
    ArgumentError -> :error
  end

  defp maybe_load({kind, _id} = key) do
    case lookup_producer(key, kind) do
      {_target, server, :sync, false} ->
        if GenServer.whereis(server) != self() do
          try do
            GenServer.call(server, :ensure_loaded, @load_timeout)
            :loaded
          catch
            :exit, _reason -> :miss
          end
        else
          :miss
        end

      {_target, server, :async, false} ->
        if GenServer.whereis(server) != self(), do: GenServer.cast(server, :wake)
        :miss

      _already_loaded_or_none ->
        :miss
    end
  end

  defp lookup_producer(key, kind) do
    case :ets.lookup(@producers, {:key, key}) do
      [entry] ->
        entry

      [] ->
        case :ets.lookup(@producers, {:kind, kind}) do
          [entry] -> entry
          [] -> nil
        end
    end
  rescue
    ArgumentError -> nil
  end

  defp producer_target({kind, id})
       when is_map_key(@kinds, kind) and (is_integer(id) or is_binary(id)),
       do: {:key, {kind, id}}

  defp producer_target(kind) when is_map_key(@kinds, kind), do: {:kind, kind}

  # A key is built by site code from a fixed kind and an id the site holds.
  defp checked({kind, id} = key)
       when is_map_key(@kinds, kind) and (is_integer(id) or is_binary(id)),
       do: key
end
