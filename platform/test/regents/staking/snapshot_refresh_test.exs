defmodule Regents.Staking.SnapshotRefreshTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Regents.Staking.{SnapshotCache, SnapshotRefresh}

  defmodule CrashingChainClient do
    @behaviour Regents.Staking.ChainClient

    @impl true
    def protocol_snapshot(_history), do: exit(:simulated_refresh_crash)

    @impl true
    def wallet_snapshot(_wallet), do: exit(:simulated_refresh_crash)
  end

  # Pages waiting on a reading hear only what Postgres announces. A refresh that
  # crashes returns nothing, so Oban's report of it is what tells them. The job
  # runs outside the test sandbox here, so the announcement is committed and
  # reaches this machine's listener as it would on a running server.
  test "CRASH_TELLS_PAGES: a refresh that crashes tells open pages it has no reading" do
    previous = Application.get_env(:regents, :staking_chain_client)
    Application.put_env(:regents, :staking_chain_client, CrashingChainClient)
    on_exit(fn -> Application.put_env(:regents, :staking_chain_client, previous) end)
    Phoenix.PubSub.subscribe(Regents.PubSub, SnapshotCache.topic())

    Sandbox.unboxed_run(Regents.Repo, fn ->
      assert_raise Oban.CrashError, fn ->
        Oban.Testing.perform_job(SnapshotRefresh, %{key: SnapshotCache.key()}, repo: Regents.Repo)
      end
    end)

    assert_receive {:staking_snapshot_unavailable, :unavailable}, 5_000
  end
end
