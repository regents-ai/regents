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

  # audience: who may see it, and why. keys: the most this kind holds.
  # bytes: the largest reading, measured as `:erlang.external_size/1`.
  @kinds %{
    # Ten rows of about 3.6 KB at most (a name, a square pattern and a picture
    # address) and 8 bytes for each account with points: 10,000 such accounts
    # take about 116 KB.
    points_board: %{
      audience:
        "signed-in people and paired agents, the readers the Points page and the agent's " <>
          "Points answer admit; each gets the rows without account ids and their own place, " <>
          "never the list of totals (Regents.Points.Board)",
      keys: 1,
      bytes: 131_072
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
      [{^key, entry}] -> {:ok, entry}
      [] -> :error
    end
  rescue
    # No table for the instant its owner restarts: the same as no reading.
    ArgumentError -> :error
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

  # A key is built by site code from a fixed kind and an id the site holds.
  defp checked({kind, id} = key)
       when is_map_key(@kinds, kind) and (is_integer(id) or is_binary(id)),
       do: key
end
