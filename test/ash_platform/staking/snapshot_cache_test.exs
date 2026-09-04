defmodule AshPlatform.Staking.SnapshotCacheTest do
  use ExUnit.Case, async: false

  alias AshPlatform.Staking.SnapshotCache
  alias AshPlatform.TestStakingChainClient

  defmodule GatedChainClient do
    @behaviour AshPlatform.Staking.ChainClient

    @impl true
    def protocol_snapshot do
      send(Application.fetch_env!(:ash_platform, :test_staking_read_gate), {:reading, self()})

      receive do
        :continue -> AshPlatform.TestStakingChainClient.protocol_snapshot()
      after
        5_000 -> raise "timed out waiting to continue the shared reading"
      end
    end

    @impl true
    def wallet_snapshot(wallet), do: AshPlatform.TestStakingChainClient.wallet_snapshot(wallet)

    @impl true
    def allowance(wallet, amount),
      do: AshPlatform.TestStakingChainClient.allowance(wallet, amount)
  end

  defmodule CrashingChainClient do
    @behaviour AshPlatform.Staking.ChainClient

    @impl true
    def protocol_snapshot, do: exit(:simulated_reading_crash)

    @impl true
    def wallet_snapshot(_wallet), do: exit(:simulated_reading_crash)

    @impl true
    def allowance(_wallet, _amount), do: {:ok, :insufficient}
  end

  setup do
    SnapshotCache.clear()
    Phoenix.PubSub.subscribe(AshPlatform.PubSub, SnapshotCache.topic())

    on_exit(fn ->
      for key <- [
            :test_staking_protocol_error,
            :test_staking_read_gate,
            :test_staking_read_watcher,
            :test_staking_price_handler,
            :staking_shared_refreshes_per_minute,
            :staking_snapshot_boot_backoff_ms,
            :staking_snapshot_clock
          ] do
        Application.delete_env(:ash_platform, key)
      end

      SnapshotCache.clear()
    end)

    :ok
  end

  test "NO_BOOT_READ_UNDER_TEST: nothing reads Base until something asks for a reading" do
    assert SnapshotCache.snapshot() == nil
    refute_received {:staking_snapshot, _snapshot}
  end

  test "SHARED_READING: one reading is remembered and announced to every page" do
    assert :ok = SnapshotCache.refresh()
    assert_receive {:staking_snapshot, snapshot}

    assert snapshot.block_number == TestStakingChainClient.protocol_block()
    assert %DateTime{} = snapshot.read_at
    assert SnapshotCache.snapshot() == snapshot
  end

  test "ONE_READING_AT_A_TIME: pages arriving during a reading join it rather than buy another" do
    swap_client(GatedChainClient)
    Application.put_env(:ash_platform, :test_staking_read_gate, self())
    Application.put_env(:ash_platform, :test_staking_read_watcher, self())

    assert :ok = SnapshotCache.refresh()
    assert_receive {:reading, reading}

    assert :ok = SnapshotCache.refresh()
    assert :ok = SnapshotCache.refresh()
    refute_receive {:reading, _other}, 100

    send(reading, :continue)
    assert_receive {:staking_snapshot, _snapshot}

    # Exactly one reading of Base happened for the three requests.
    assert_received {:staking_read, :protocol, ^reading}
    refute_received {:staking_read, :protocol, _another}
  end

  test "MINIMUM_INTERVAL: a second reading within ten seconds is refused, not queued" do
    clock = fixed_clock(0)
    assert :ok = SnapshotCache.refresh()
    assert_receive {:staking_snapshot, first}

    clock.(9_999)
    assert {:error, :refresh_too_soon} = SnapshotCache.refresh()
    refute_receive {:staking_snapshot, _snapshot}, 100
    assert SnapshotCache.snapshot() == first

    clock.(10_000)
    assert :ok = SnapshotCache.refresh()
    assert_receive {:staking_snapshot, _second}
  end

  test "READINGS_PER_MINUTE: the server's allowance for the minute bounds shared readings" do
    Application.put_env(:ash_platform, :staking_shared_refreshes_per_minute, 2)
    clock = fixed_clock(0)

    assert :ok = SnapshotCache.refresh()
    assert_receive {:staking_snapshot, _first}

    clock.(11_000)
    assert :ok = SnapshotCache.refresh()
    assert_receive {:staking_snapshot, _second}

    clock.(22_000)
    assert {:error, :refresh_too_soon} = SnapshotCache.refresh()

    # The allowance is a trailing minute, not a total: it comes back.
    clock.(62_000)
    assert :ok = SnapshotCache.refresh()
    assert_receive {:staking_snapshot, _third}
  end

  test "FAILED_READING: the last good reading stays and only the pages that asked hear" do
    assert :ok = SnapshotCache.refresh()
    assert_receive {:staking_snapshot, first}

    clock = fixed_clock(11_000)
    Application.put_env(:ash_platform, :test_staking_protocol_error, :provider_failure)

    assert :ok = SnapshotCache.refresh()
    assert_receive {:staking_snapshot_unavailable, :provider_failure}
    refute_received {:staking_snapshot, _replacement}
    assert SnapshotCache.snapshot() == first

    # A reading is available again straight after, once the interval allows it.
    Application.delete_env(:ash_platform, :test_staking_protocol_error)
    clock.(22_000)
    assert :ok = SnapshotCache.refresh()
    assert_receive {:staking_snapshot, _second}
  end

  # An endpoint that is down exactly at startup would otherwise leave every
  # visitor on the unavailable state until a signed-in person happened to
  # arrive, so the server keeps trying for its own first reading.
  test "BOOT_RETRY: a failed first reading is retried, bounded, and stops once one lands" do
    enable_boot_read()
    Application.put_env(:ash_platform, :staking_snapshot_boot_backoff_ms, 1)
    Application.put_env(:ash_platform, :test_staking_protocol_error, :provider_failure)
    Application.put_env(:ash_platform, :test_staking_read_watcher, self())

    send(SnapshotCache, {:boot_read, 1})

    # It tries again rather than giving up on the one failure.
    for _attempt <- 1..3, do: assert_receive({:staking_read, :protocol, _reader}, 1_000)

    # Base comes back, and the reading that lands is remembered and announced.
    Application.delete_env(:ash_platform, :test_staking_protocol_error)
    assert_receive {:staking_snapshot, snapshot}, 1_000
    assert SnapshotCache.snapshot() == snapshot

    # Nothing keeps reading once there is a reading to show.
    drain_reads()
    refute_receive {:staking_read, :protocol, _reader}, 100
  end

  test "BOOT_RETRY_IS_BOUNDED: an endpoint that never answers is not retried forever" do
    enable_boot_read()
    Application.put_env(:ash_platform, :staking_snapshot_boot_backoff_ms, 1)
    Application.put_env(:ash_platform, :test_staking_protocol_error, :provider_failure)
    Application.put_env(:ash_platform, :test_staking_read_watcher, self())

    send(SnapshotCache, {:boot_read, 1})

    for _attempt <- 1..SnapshotCache.boot_attempts() do
      assert_receive {:staking_read, :protocol, _reader}, 1_000
    end

    refute_receive {:staking_read, :protocol, _reader}, 200
    assert SnapshotCache.snapshot() == nil

    # Having given up, the server has spent none of the allowance that bounds
    # what visitors may ask for, so the first person to ask is not refused.
    Application.delete_env(:ash_platform, :test_staking_protocol_error)
    assert :ok = SnapshotCache.refresh()
    assert_receive {:staking_snapshot, _snapshot}, 1_000
  end

  # An attempt that comes due while a visitor's reading is already running has
  # nothing to gain from starting a second one, and abandoning the chain on that
  # visitor's timing would leave the server with no first reading of its own. The
  # attempt rides along with the reading in flight instead, and a reading that
  # fails still arms the next attempt.
  test "BOOT_READ_JOINS_A_READING: an attempt that rides along still arms the next one" do
    enable_boot_read()
    Application.put_env(:ash_platform, :staking_snapshot_boot_backoff_ms, 1)
    Application.put_env(:ash_platform, :test_staking_read_gate, self())
    swap_client(GatedChainClient)

    # A visitor's reading holds the one reading slot.
    assert :ok = SnapshotCache.refresh()
    assert_receive {:reading, visitor_reading}

    # The server's own attempt comes due while that reading is still running and
    # buys no second reading of Base.
    send(SnapshotCache, {:boot_read, 1})
    assert SnapshotCache.snapshot() == nil
    refute_receive {:reading, _second}, 100

    # The reading it joined fails, so the next attempt follows.
    Application.put_env(:ash_platform, :test_staking_protocol_error, :provider_failure)
    send(visitor_reading, :continue)
    assert_receive {:staking_snapshot_unavailable, :provider_failure}
    assert_receive {:reading, retried}, 1_000

    Application.delete_env(:ash_platform, :test_staking_protocol_error)
    send(retried, :continue)
    assert_receive {:staking_snapshot, snapshot}, 1_000
    assert SnapshotCache.snapshot() == snapshot
  end

  test "QUOTE_IS_CACHED: a user refresh inside 120s rereads the chain and keeps the quote" do
    test = self()
    stub_quote(fn url -> send(test, {:price_http, url}) end)
    clock = fixed_clock(0)

    assert :ok = SnapshotCache.refresh()
    assert_receive {:staking_snapshot, first}
    assert first.regent_price_usd == "0.000006"
    assert_received {:price_http, pair_url}
    assert_received {:price_http, token_url}
    assert pair_url =~ "/pairs/"
    assert token_url =~ "/tokens/"

    clock.(10_000)
    assert :ok = SnapshotCache.refresh()
    assert_receive {:staking_snapshot, second}
    assert second.regent_price_usd == first.regent_price_usd
    refute_received {:price_http, _}
  end

  test "QUOTE_REFETCH: a user refresh after 120s fetches the quote again" do
    test = self()
    stub_quote(fn url -> send(test, {:price_http, url}) end)
    clock = fixed_clock(0)

    assert :ok = SnapshotCache.refresh()
    assert_receive {:staking_snapshot, _first}
    assert_received {:price_http, _}
    assert_received {:price_http, _}

    clock.(120_000)
    assert :ok = SnapshotCache.refresh()
    assert_receive {:staking_snapshot, second}
    assert second.regent_price_usd == "0.000006"
    assert_received {:price_http, _}
    assert_received {:price_http, _}
  end

  test "CRASHED_READING: a reading that died is reported and changes nothing" do
    assert :ok = SnapshotCache.refresh()
    assert_receive {:staking_snapshot, first}

    fixed_clock(11_000)
    swap_client(CrashingChainClient)

    assert :ok = SnapshotCache.refresh()
    assert_receive {:staking_snapshot_unavailable, :unavailable}
    assert SnapshotCache.snapshot() == first
  end

  defp enable_boot_read do
    previous = Application.get_env(:ash_platform, :staking_snapshot_boot_read)
    Application.put_env(:ash_platform, :staking_snapshot_boot_read, true)

    on_exit(fn ->
      Application.put_env(:ash_platform, :staking_snapshot_boot_read, previous)
      SnapshotCache.clear()
    end)
  end

  defp drain_reads do
    receive do
      {:staking_read, :protocol, _reader} -> drain_reads()
    after
      50 -> :ok
    end
  end

  defp stub_quote(on_get) do
    Application.put_env(:ash_platform, :test_staking_price_handler, fn url ->
      on_get.(url)

      {:ok,
       %{
         status: 200,
         body: AshPlatform.TestStakingPriceHttpClient.quote_body(url, "0.000000002", "3000")
       }}
    end)
  end

  defp swap_client(module) do
    previous = Application.get_env(:ash_platform, :staking_chain_client)
    Application.put_env(:ash_platform, :staking_chain_client, module)
    on_exit(fn -> Application.put_env(:ash_platform, :staking_chain_client, previous) end)
  end

  # A clock the test moves by hand, so a bound measured in seconds is proved
  # without spending them.
  defp fixed_clock(start) do
    {:ok, agent} = Agent.start_link(fn -> start end)

    Application.put_env(
      :ash_platform,
      :staking_snapshot_clock,
      fn -> Agent.get(agent, & &1) end
    )

    fn at -> Agent.update(agent, fn _now -> at end) end
  end
end
