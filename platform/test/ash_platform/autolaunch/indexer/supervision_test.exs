defmodule AshPlatform.Autolaunch.Indexer.SupervisionTest do
  @moduledoc """
  Where the indexer is allowed to run, and what a failing pass is allowed to
  take down with it.

  The test runtime owns its endpoint setting outright, so an exported shell
  variable can never start an indexer under a test run, and a transport failure
  reports a method and an error class without the endpoint that produced it.
  """

  use AshPlatform.AutolaunchIndexerCase, async: false

  import ExUnit.CaptureLog

  alias AshPlatform.Autolaunch.Indexer.Handler
  alias AshPlatform.DurableWork.Runner
  alias AshPlatform.TestAutolaunchIndexerChainClient, as: Endpoint

  @auction "0x00000000000000000000000000000000000000aa"
  @endpoint "https://base-mainnet.example.invalid/v2/8f3c1d9e-provider-key"

  test "the test runtime configures no endpoint and supervises no indexer" do
    assert Application.get_env(:ash_platform, :autolaunch_indexer_rpc_url) == nil

    refute Enum.any?(
             Supervisor.which_children(AshPlatform.Supervisor),
             &match?({Runner, _pid, _type, _modules}, &1)
           )
  end

  test "a transport failure reports a method and a class, never the endpoint" do
    configure_endpoint()
    start_endpoint(chain(blocks(10..12), safe: 12, fault: {:raise, "econnrefused #{@endpoint}"}))
    assert {:ok, _source} = admit(@auction, 10)

    diagnostic = capture_log(fn -> assert pass() == {:error, :chain_unavailable} end)

    refute diagnostic =~ @endpoint
    refute diagnostic =~ "provider-key"
    assert diagnostic =~ "eth_chainId"
    assert diagnostic =~ "class: :transport"

    assert cursor().next_block_to_fetch == 10
    assert stored_blocks() == []
  end

  test "a provider that answers wrongly reports a class, never the endpoint or its body" do
    configure_endpoint()
    start_endpoint(chain(blocks(10..12), safe: 12))
    assert {:ok, _source} = admit(@auction, 10)

    for {fault, class} <- [{{:status, 503}, ":http"}, {:rpc_error, ":rpc"}, {:foreign_id, ":rpc"}] do
      Endpoint.script(chain(blocks(10..12), safe: 12, fault: fault))

      diagnostic = capture_log(fn -> assert pass() == {:error, :chain_unavailable} end)

      assert diagnostic =~ "class: #{class}"
      refute diagnostic =~ @endpoint
      refute diagnostic =~ "provider-key"
      refute diagnostic =~ "32000"
    end

    assert stored_blocks() == []
    assert cursor().next_block_to_fetch == 10
  end

  test "a failing pass leaves the runner polling and the application supervisor untouched" do
    configure_endpoint()
    start_endpoint(chain(blocks(10..12), safe: 12, fault: {:raise, "econnrefused #{@endpoint}"}))

    # The runner's handler process shares this connection, so the source it must
    # find is admitted through the sandbox rather than committed.
    assert {:ok, _source} = Handler.admit_source(@auction, 10)
    Endpoint.watch()

    capture_log(fn ->
      runner =
        start_supervised!({Runner, handler: Handler, poll_interval_ms: 10, max_in_flight: 1})

      assert_receive {:rpc, "eth_chainId"}, 5_000
      assert_receive {:rpc, "eth_chainId"}, 5_000

      assert Process.alive?(runner)
      assert Process.alive?(Process.whereis(AshPlatform.Supervisor))

      # The runner goes down, and the pass it last dispatched finishes, while
      # this test still owns the connection they both borrowed.
      stop_supervised!(Runner)

      # The stop returns with the runner and its work already down, so anything
      # waiting in this mailbox was announced by the runner while it was still
      # running. Clearing it leaves the refutation below saying the one thing it
      # means: a stopped runner dispatches nothing more.
      drain_announcements()
      refute_receive {:rpc, "eth_chainId"}, 100
    end)
  end

  # Every announcement already waiting, and never a wait for one to arrive.
  defp drain_announcements do
    receive do
      {:rpc, _method} -> drain_announcements()
    after
      0 -> :ok
    end
  end

  defp configure_endpoint do
    Application.put_env(:ash_platform, :autolaunch_indexer_rpc_url, @endpoint)
    on_exit(fn -> Application.put_env(:ash_platform, :autolaunch_indexer_rpc_url, nil) end)
  end
end
