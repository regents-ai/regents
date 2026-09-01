defmodule AshPlatform.OpenSea.HoldingsCacheTest do
  use ExUnit.Case, async: false

  alias AshPlatform.OpenSea.HoldingsCache

  @first "0x1111111111111111111111111111111111111111"
  @second "0x2222222222222222222222222222222222222222"
  @third "0x3333333333333333333333333333333333333333"
  @fourth "0x4444444444444444444444444444444444444444"

  setup do
    HoldingsCache.clear()
    previous_ceiling = Application.get_env(:ash_platform, :opensea_holdings_max_in_flight)
    previous_window = Application.get_env(:ash_platform, :opensea_holdings_cache_ttl_ms)

    on_exit(fn ->
      restore(:opensea_holdings_max_in_flight, previous_ceiling)
      restore(:opensea_holdings_cache_ttl_ms, previous_window)
      HoldingsCache.clear()
    end)

    :ok
  end

  test "CACHE_WINDOW: a repeated lookup answers from the window without a second read" do
    assert {:ok, :held} = HoldingsCache.fetch(@first, loader(@first, {:ok, :held}))
    assert_receive {:loader_started, @first}

    assert {:ok, :held} = HoldingsCache.fetch(@first, loader(@first, {:ok, :other}))
    assert {:ok, :held} = HoldingsCache.fetch(@first, loader(@first, {:ok, :other}))
    refute_receive {:loader_started, _address}, 100
  end

  test "LIVE_READ_CEILING: an address past the ceiling is unavailable and never read" do
    Application.put_env(:ash_platform, :opensea_holdings_max_in_flight, 2)
    held = for address <- [@first, @second], do: blocked_lookup(address)

    assert {:error, :unavailable} = HoldingsCache.fetch(@third, loader(@third, {:ok, :held}))
    refute_receive {:loader_started, @third}, 100

    [%{address: address} = finished | still_running] = held
    release(finished)
    assert {:ok, ^address} = Task.await(finished.lookup)

    assert {:ok, :held} = HoldingsCache.fetch(@fourth, loader(@fourth, {:ok, :held}))
    assert_receive {:loader_started, @fourth}

    for lookup <- still_running do
      release(lookup)
      Task.await(lookup.lookup)
    end
  end

  test "RESET_HOLDS_ITS_SLOT: a reset during a live read frees no room and caches nothing" do
    Application.put_env(:ash_platform, :opensea_holdings_max_in_flight, 1)
    running = blocked_lookup(@first)

    HoldingsCache.invalidate(@first)

    assert {:error, :unavailable} = HoldingsCache.fetch(@second, loader(@second, {:ok, :held}))
    refute_receive {:loader_started, @second}, 100

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

  test "DEAD_LOADER: a read that dies without answering frees its slot and its waiters" do
    Application.put_env(:ash_platform, :opensea_holdings_max_in_flight, 1)
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

  test "CEILING_ADMITS_WAITERS: a second page joins a running read at the ceiling" do
    Application.put_env(:ash_platform, :opensea_holdings_max_in_flight, 1)
    running = blocked_lookup(@first)

    joined = Task.async(fn -> HoldingsCache.fetch(@first, loader(@first, {:ok, :other})) end)
    assert {:error, :unavailable} = HoldingsCache.fetch(@second, loader(@second, {:ok, :held}))

    release(running)
    assert {:ok, @first} = Task.await(running.lookup)
    assert {:ok, @first} = Task.await(joined)
    refute_receive {:loader_started, _address}, 100
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

  defp restore(key, nil), do: Application.delete_env(:ash_platform, key)
  defp restore(key, value), do: Application.put_env(:ash_platform, key, value)
end
