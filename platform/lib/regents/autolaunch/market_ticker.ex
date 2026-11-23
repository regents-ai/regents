defmodule Regents.Autolaunch.MarketTicker do
  @moduledoc """
  The recent bids and trades the ticker at the foot of every page shows, read
  once and shared by every page that has it open.

  A saved bid or trade rereads them a second later, so a burst of them costs
  one read, and a list that differs from the last goes out to every page as
  `{:market_ticker, entries}`. Entries leave the list an hour after they
  happened; when the list holds entries, one timer wakes at the oldest entry's
  expiry, and when the list is empty no periodic reads run. The list holds at
  most the twenty newest bids and the twenty newest trades of that hour.
  """

  use GenServer

  alias Regents.Autolaunch
  alias Regents.ProductActivity

  @topic "market_ticker"
  @coalesce_ms 1_000
  @entry_ttl_ms :timer.hours(1)

  def topic, do: @topic

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc "The current list, newest first; each later one arrives as `{:market_ticker, entries}`."
  def subscribe do
    Phoenix.PubSub.subscribe(Regents.PubSub, @topic)

    case :ets.lookup(__MODULE__, :entries) do
      [{:entries, entries, true}] ->
        entries

      _unloaded ->
        ensure_loaded()

        case :ets.lookup(__MODULE__, :entries) do
          [{:entries, entries, _loaded?}] -> entries
          [] -> []
        end
    end
  end

  defp ensure_loaded do
    GenServer.call(__MODULE__, :ensure_loaded, 10_000)
  catch
    :exit, _reason -> :ok
  end

  @impl true
  def init(nil) do
    :ets.new(__MODULE__, [:named_table, :protected, read_concurrency: true])
    :ets.insert(__MODULE__, {:entries, [], false})
    ProductActivity.subscribe()
    Regents.Autolaunch.Listings.subscribe()
    Regents.Autolaunch.TokenTrades.subscribe()
    {:ok, %{due: false, loaded?: false, expiry_timer: nil}}
  end

  @impl true
  def handle_call(:ensure_loaded, _from, %{loaded?: true} = state), do: {:reply, :ok, state}

  def handle_call(:ensure_loaded, _from, state) do
    ProductActivity.touch(:autolaunch)
    state = load_entries(state)
    {:reply, :ok, %{state | loaded?: true}}
  end

  @impl true
  def handle_info({:product_idle, :autolaunch}, %{loaded?: true} = state) do
    if state.expiry_timer, do: Process.cancel_timer(state.expiry_timer)
    :ets.insert(__MODULE__, {:entries, [], false})
    {:noreply, %{state | due: false, loaded?: false, expiry_timer: nil}}
  end

  def handle_info({:product_idle, _product}, state), do: {:noreply, state}
  def handle_info({:product_active, _product}, state), do: {:noreply, state}

  def handle_info({event, _id}, %{due: false, loaded?: true} = state)
      when event in [:autolaunch_listings_changed, :autolaunch_trade] do
    if ProductActivity.active?(:autolaunch) do
      Process.send_after(self(), :load, @coalesce_ms)
      {:noreply, %{state | due: true}}
    else
      {:noreply, state}
    end
  end

  def handle_info({event, _id}, state)
      when event in [:autolaunch_listings_changed, :autolaunch_trade],
      do: {:noreply, state}

  def handle_info(:load, %{loaded?: true} = state) do
    if ProductActivity.active?(:autolaunch) do
      {:noreply, load_entries(state)}
    else
      if state.expiry_timer, do: Process.cancel_timer(state.expiry_timer)
      :ets.insert(__MODULE__, {:entries, [], false})
      {:noreply, %{state | due: false, loaded?: false, expiry_timer: nil}}
    end
  end

  def handle_info(:load, state), do: {:noreply, %{state | due: false}}

  defp load_entries(state) do
    if state.expiry_timer, do: Process.cancel_timer(state.expiry_timer)

    expiry_timer =
      with {:ok, bids} <- Autolaunch.recent_bid_activity(actor: nil),
           {:ok, trades} <- Autolaunch.recent_token_trades(actor: nil) do
        entries = entries(bids, trades)

        # Most rereads find the same list; only a new one goes out to the pages.
        if :ets.lookup(__MODULE__, :entries) != [{:entries, entries, true}] do
          :ets.insert(__MODULE__, {:entries, entries, true})
          Phoenix.PubSub.broadcast(Regents.PubSub, @topic, {:market_ticker, entries})
        end

        schedule_expiry(entries)
      else
        _error -> nil
      end

    %{state | due: false, expiry_timer: expiry_timer}
  end

  # When the list is empty, nothing can age out; PubSub wakes the ticker when a
  # new bid or trade lands. Otherwise wake once the oldest entry turns an hour old.
  defp schedule_expiry([]), do: nil

  defp schedule_expiry(entries) do
    oldest_at =
      entries
      |> Enum.map(fn {_kind, entry} -> entry.occurred_at end)
      |> Enum.min(DateTime)

    age_ms = DateTime.diff(DateTime.utc_now(), oldest_at, :millisecond)
    wait_ms = max(@coalesce_ms, @entry_ttl_ms - age_ms + 500)
    Process.send_after(self(), :load, wait_ms)
  end

  # Bids and trades together, newest first. Base makes several blocks in one
  # second, so entries that share a second follow the chain's own order.
  defp entries(bids, trades) do
    bids = for %{auction: %{}} = bid <- bids, do: {:bid, bid}
    trades = for %{token: %{auction: %{}}} = trade <- trades, do: {:trade, trade}

    Enum.sort_by(bids ++ trades, fn {_, entry} -> position(entry) end, :desc)
  end

  defp position(entry),
    do: {DateTime.to_unix(entry.occurred_at, :microsecond), entry.block_number, entry.log_index}
end
