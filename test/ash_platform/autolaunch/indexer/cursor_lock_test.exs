defmodule AshPlatform.Autolaunch.Indexer.CursorLockTest do
  @moduledoc """
  What the shared cursor row lock guarantees, proven on real second connections.

  PostgreSQL reports the ordering through `pg_blocking_pids`, so nothing here
  waits on a clock: a source admission and a range commit contend for one lock,
  and a lease admits exactly one writer while still letting the next pass start
  as soon as the last one lets go.
  """

  use AshPlatform.AutolaunchIndexerCase, async: false

  alias AshPlatform.Autolaunch.Indexer.{Handler, Ledger}

  @auction "0x00000000000000000000000000000000000000aa"
  @late "0x00000000000000000000000000000000000000bb"

  setup do
    start_endpoint(chain(blocks(10..14), safe: 12, finalized: 10))
    {:ok, _source} = admit(@auction, 10)
    :ok
  end

  test "an admission that rewinds the cursor orders ahead of a range planned from the old one" do
    {:ok, lease} = unboxed(fn -> Ledger.acquire(chain_id(), Handler.lease_ms()) end)
    assert lease.next_block == 10

    admission = holding(fn -> Handler.admit_source(@late, 5) end)
    commit = contending(fn -> Ledger.commit(lease, planned_range(), Handler.bound()) end)

    assert_blocked_by(commit, admission)
    assert {:ok, _source} = release(admission)

    # The commit takes the lock second, sees a cursor that is no longer the one
    # its range was planned from, and rolls the whole range back.
    assert settled(commit) == {:error, :lease_lost}
    assert cursor().next_block_to_fetch == 5
    assert stored_blocks() == []
  end

  test "one lease admits one writer, and the next pass starts as soon as it is released" do
    granting = holding(fn -> Ledger.acquire(chain_id(), Handler.lease_ms()) end)
    rival = contending(fn -> Ledger.acquire(chain_id(), Handler.lease_ms()) end)

    assert_blocked_by(rival, granting)
    assert {:ok, lease} = release(granting)

    assert settled(rival) == {:error, :leased}

    # Forward progress needs no expiry: releasing the lease admits the next pass.
    assert {:ok, _released} = unboxed(fn -> Ledger.release(lease) end)
    assert {:ok, next} = unboxed(fn -> Ledger.acquire(chain_id(), Handler.lease_ms()) end)
    assert next.next_block == 10
    assert next.owner != lease.owner
  end

  test "a commit under a lease another writer replaced advances nothing" do
    {:ok, stale} = unboxed(fn -> Ledger.acquire(chain_id(), Handler.lease_ms()) end)
    assert {:ok, _released} = unboxed(fn -> Ledger.release(stale) end)
    assert {:ok, _live} = unboxed(fn -> Ledger.acquire(chain_id(), Handler.lease_ms()) end)

    assert unboxed(fn -> Ledger.commit(stale, planned_range(), Handler.bound()) end) ==
             {:error, :lease_lost}

    assert cursor().next_block_to_fetch == 10
    assert stored_blocks() == []
  end

  defp planned_range do
    headers =
      Enum.map(10..12, fn number ->
        %{number: number, hash: block_hash(number), parent_hash: block_hash(number - 1)}
      end)

    {:range, headers, [], %{number: 10, hash: block_hash(10)}}
  end
end
