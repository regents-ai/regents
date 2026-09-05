defmodule AshPlatform.OpenSea.HoldingsCacheTest do
  use ExUnit.Case, async: false

  alias AshPlatform.OpenSea.HoldingsCache

  @first "0x1111111111111111111111111111111111111111"
  @second "0x2222222222222222222222222222222222222222"
  @third "0x3333333333333333333333333333333333333333"
  @fourth "0x4444444444444444444444444444444444444444"
  @start_ms 1_000_000

  setup do
    HoldingsCache.clear()
    previous_clock = Application.get_env(:ash_platform, :opensea_holdings_clock)
    previous_minute = Application.get_env(:ash_platform, :opensea_live_lookups_per_minute)
    previous_window = Application.get_env(:ash_platform, :opensea_holdings_cache_ttl_ms)

    # The server's minute is read off a counter the test moves by hand, so a
    # sliding window is proven by stepping time rather than by waiting for it.
    clock = :counters.new(1, [])
    :counters.add(clock, 1, @start_ms)
    Application.put_env(:ash_platform, :opensea_holdings_clock, fn -> :counters.get(clock, 1) end)

    on_exit(fn ->
      restore(:opensea_holdings_clock, previous_clock)
      restore(:opensea_live_lookups_per_minute, previous_minute)
      restore(:opensea_holdings_cache_ttl_ms, previous_window)
      HoldingsCache.clear()
    end)

    %{clock: clock}
  end

  test "CACHE_WINDOW: a repeated lookup answers from the window without a second read" do
    assert {:ok, :held} = HoldingsCache.fetch(@first, loader(@first, {:ok, :held}))
    assert_receive {:loader_started, @first}

    assert {:ok, :held} = HoldingsCache.fetch(@first, loader(@first, {:ok, :other}))
    assert {:ok, :held} = HoldingsCache.fetch(@first, loader(@first, {:ok, :other}))
    refute_receive {:loader_started, _address}, 100
  end

  test "SERVER_MINUTE: the lookup past the server's minute is unavailable and never read" do
    for number <- 1..60 do
      address = address(number)
      assert {:ok, :held} = HoldingsCache.fetch(address, loader(address, {:ok, :held}))
      assert_receive {:loader_started, ^address}
    end

    past = address(61)
    assert {:error, :unavailable} = HoldingsCache.fetch(past, loader(past, {:ok, :held}))
    refute_receive {:loader_started, _address}, 100
  end

  test "MINUTE_SLIDES: a start leaves the server's minute exactly a minute after it began", %{
    clock: clock
  } do
    Application.put_env(:ash_platform, :opensea_live_lookups_per_minute, 2)

    assert {:ok, :held} = HoldingsCache.fetch(@first, loader(@first, {:ok, :held}))
    assert_receive {:loader_started, @first}

    advance(clock, 30_000)
    assert {:ok, :held} = HoldingsCache.fetch(@second, loader(@second, {:ok, :held}))
    assert_receive {:loader_started, @second}

    assert {:error, :unavailable} = HoldingsCache.fetch(@third, loader(@third, {:ok, :held}))
    refute_receive {:loader_started, @third}, 100

    # Exactly a minute after the first read, its place is free again while the
    # second read, half a minute younger, still holds its own.
    advance(clock, 30_000)
    assert {:ok, :held} = HoldingsCache.fetch(@third, loader(@third, {:ok, :held}))
    assert_receive {:loader_started, @third}

    assert {:error, :unavailable} = HoldingsCache.fetch(@fourth, loader(@fourth, {:ok, :held}))
    refute_receive {:loader_started, @fourth}, 100

    advance(clock, 30_000)
    assert {:ok, :held} = HoldingsCache.fetch(@fourth, loader(@fourth, {:ok, :held}))
    assert_receive {:loader_started, @fourth}
  end

  test "JOINING_IS_FREE: a page waiting on a running read spends none of the server's minute" do
    Application.put_env(:ash_platform, :opensea_live_lookups_per_minute, 2)
    running = blocked_lookup(@first)

    joined = Task.async(fn -> HoldingsCache.fetch(@first, loader(@first, {:ok, :other})) end)
    await_waiters(@first, 2)

    assert {:ok, :held} = HoldingsCache.fetch(@second, loader(@second, {:ok, :held}))
    assert_receive {:loader_started, @second}

    assert {:error, :unavailable} = HoldingsCache.fetch(@third, loader(@third, {:ok, :held}))
    refute_receive {:loader_started, @third}, 100

    release(running)
    assert {:ok, @first} = Task.await(running.lookup)
    assert {:ok, @first} = Task.await(joined)
  end

  test "CACHED_IS_FREE: an answer from the window spends none of the server's minute" do
    Application.put_env(:ash_platform, :opensea_live_lookups_per_minute, 2)

    assert {:ok, :held} = HoldingsCache.fetch(@first, loader(@first, {:ok, :held}))
    assert_receive {:loader_started, @first}

    for _ <- 1..5 do
      assert {:ok, :held} = HoldingsCache.fetch(@first, loader(@first, {:ok, :other}))
    end

    assert {:ok, :held} = HoldingsCache.fetch(@second, loader(@second, {:ok, :held}))
    assert_receive {:loader_started, @second}

    assert {:error, :unavailable} = HoldingsCache.fetch(@third, loader(@third, {:ok, :held}))
    refute_receive {:loader_started, _address}, 100
  end

  test "RESET_DURING_READ: a reset mid-read hands out nothing and caches nothing" do
    running = blocked_lookup(@first)

    HoldingsCache.invalidate(@first)

    assert {:error, :unavailable} = HoldingsCache.fetch(@first, loader(@first, {:ok, :stale}))
    refute_receive {:loader_started, @first}, 100

    release(running)
    assert {:ok, @first} = Task.await(running.lookup)

    assert {:ok, :fresh} = HoldingsCache.fetch(@first, loader(@first, {:ok, :fresh}))
    assert_receive {:loader_started, @first}
  end

  test "RESET_ANSWERS_WAITERS: a page waiting on an abandoned read is told the lookup failed" do
    running = blocked_lookup(@first)

    HoldingsCache.clear()

    assert {:error, :unavailable} = Task.await(running.lookup)
    release(running)
  end

  test "DEAD_LOADER: a read that dies without answering answers its waiters and is forgotten" do
    test_pid = self()

    # The real read runs its provider requests in linked tasks, so a crash in one
    # of them kills the loader outright, before it can report anything back.
    dying = fn ->
      send(test_pid, {:loader_started, @first})
      Process.exit(self(), :kill)
    end

    waiter = Task.async(fn -> HoldingsCache.fetch(@first, dying) end)
    assert_receive {:loader_started, @first}
    assert {:error, :unavailable} = Task.await(waiter)

    assert {:ok, :held} = HoldingsCache.fetch(@second, loader(@second, {:ok, :held}))
    assert_receive {:loader_started, @second}

    assert {:ok, :fresh} = HoldingsCache.fetch(@first, loader(@first, {:ok, :fresh}))
    assert_receive {:loader_started, @first}
  end

  test "INVALIDATE_COOLDOWN: one reset per address per window survives a repeating page" do
    assert {:ok, :first} = HoldingsCache.fetch(@first, loader(@first, {:ok, :first}))
    assert_receive {:loader_started, @first}

    HoldingsCache.invalidate(@first)
    assert {:ok, :second} = HoldingsCache.fetch(@first, loader(@first, {:ok, :second}))
    assert_receive {:loader_started, @first}

    for _ <- 1..5 do
      HoldingsCache.invalidate(@first)
      assert {:ok, :second} = HoldingsCache.fetch(@first, loader(@first, {:ok, :third}))
    end

    refute_receive {:loader_started, _address}, 100
  end

  test "COOLDOWN_IS_PER_ADDRESS: one wallet's reset leaves another wallet's window alone" do
    for address <- [@first, @second] do
      assert {:ok, :held} = HoldingsCache.fetch(address, loader(address, {:ok, :held}))
      assert_receive {:loader_started, ^address}
    end

    HoldingsCache.invalidate(@first)
    HoldingsCache.invalidate(@second)

    for address <- [@first, @second] do
      assert {:ok, :fresh} = HoldingsCache.fetch(address, loader(address, {:ok, :fresh}))
      assert_receive {:loader_started, ^address}
    end
  end

  test "EXPIRED_WINDOW: a read runs again once the window has passed" do
    Application.put_env(:ash_platform, :opensea_holdings_cache_ttl_ms, 0)

    for _ <- 1..3 do
      assert {:ok, :held} = HoldingsCache.fetch(@first, loader(@first, {:ok, :held}))
      assert_receive {:loader_started, @first}
    end
  end

  defp loader(address, result) do
    test_pid = self()

    fn ->
      send(test_pid, {:loader_started, address})
      result
    end
  end

  defp blocked_lookup(address) do
    test_pid = self()

    lookup =
      Task.async(fn ->
        HoldingsCache.fetch(address, fn ->
          send(test_pid, {:loader_holding, address, self()})

          receive do
            :finish -> {:ok, address}
          end
        end)
      end)

    assert_receive {:loader_holding, ^address, loader}
    %{address: address, lookup: lookup, loader: loader}
  end

  defp release(%{loader: loader}), do: send(loader, :finish)

  # A joining page blocks until the read it joined answers, so the join is
  # awaited on the cache's own books rather than by guessing at a delay.
  defp await_waiters(address, count, attempts \\ 100)

  defp await_waiters(address, count, 0),
    do: flunk("#{count} pages never joined the read on #{address}")

  defp await_waiters(address, count, attempts) do
    case :sys.get_state(HoldingsCache).in_flight[address] do
      %{waiters: waiters} when length(waiters) >= count ->
        :ok

      _ ->
        Process.sleep(1)
        await_waiters(address, count, attempts - 1)
    end
  end

  defp advance(clock, milliseconds), do: :counters.add(clock, 1, milliseconds)

  defp address(number),
    do: "0x" <> String.pad_leading(Integer.to_string(number), 40, "0")

  defp restore(key, nil), do: Application.delete_env(:ash_platform, key)
  defp restore(key, value), do: Application.put_env(:ash_platform, key, value)
end
