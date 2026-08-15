defmodule AshPlatform.Autolaunch.Indexer.Ledger do
  @moduledoc """
  Every durable transition the Base ledger makes, and the row lock that orders
  them.

  Source admission and every commit ensure the chain's cursor row and then take
  the same `FOR UPDATE` lock on it, so an admission that rewinds the cursor and
  a range planned from the old position can never interleave: whichever reaches
  the lock second sees the other's decision, and a commit whose lease or exact
  planned cursor no longer holds rolls the whole range back rather than skipping
  or overwriting one.

  Provider work never happens inside these transactions. Headers and logs are
  inserted, never updated: the unique identity decides a duplicate race and a
  replay that disagrees with stored evidence aborts the transaction instead of
  rewriting it.
  """

  require Ash.Query

  alias AshPlatform.Actors.System
  alias AshPlatform.Autolaunch.Indexer.{Block, Chain, Cursor, Log, Source}
  alias AshPlatform.Repo

  @actor %System{}

  @typedoc "What a granted lease permits: this owner, this chain, this exact position."
  @type lease :: %{chain_id: pos_integer(), owner: String.t(), next_block: non_neg_integer()}

  @doc """
  Admits one normalized source and pulls the chain cursor back to cover it.

  The first admission creates the cursor at the source's start block; a later
  one behind the cursor rewinds it, so the new address is backfilled while the
  logs already stored replay as no-ops. Re-stating an address the ledger already
  watches from the same block is the same fact twice and moves nothing; naming a
  different start block for it is a contradiction and fails closed.
  """
  @spec admit_source(pos_integer(), String.t(), non_neg_integer()) ::
          {:ok, Ash.Resource.record()} | {:error, term()}
  def admit_source(chain_id, address, start_block) do
    case Chain.address(address) do
      {:ok, address} -> Repo.transaction(fn -> admit(chain_id, address, start_block) end)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Grants the chain lease to one handler, or reports that a live owner keeps it."
  @spec acquire(pos_integer(), pos_integer()) :: {:ok, lease()} | {:error, atom()}
  def acquire(chain_id, lease_ms) do
    Repo.transaction(fn ->
      case lock(chain_id) do
        nil -> Repo.rollback(:no_source_admitted)
        cursor -> claim(cursor, db_now(), lease_ms)
      end
    end)
  end

  @doc "Releases the lease this owner still holds, so the next cadence starts immediately."
  @spec release(lease()) :: {:ok, term()}
  def release(%{chain_id: chain_id, owner: owner}) do
    Repo.transaction(fn -> chain_id |> lock() |> relinquish(owner) end)
  end

  @doc "Every address admitted for a chain, ascending by the block it starts at."
  @spec sources(pos_integer()) :: [Ash.Resource.record()]
  def sources(chain_id) do
    Source
    |> Ash.Query.for_read(:for_chain, %{chain_id: chain_id})
    |> Ash.read!(actor: @actor)
  end

  @doc "The canonical block stored at an exact height, or `nil`."
  @spec canonical_block(pos_integer(), non_neg_integer()) :: Ash.Resource.record() | nil
  def canonical_block(chain_id, block_number),
    do: chain_id |> canonical_range(block_number, block_number) |> List.first()

  @doc "Whether this chain already holds that block hash as an abandoned fork."
  @spec abandoned?(pos_integer(), String.t()) :: boolean()
  def abandoned?(chain_id, block_hash),
    do: chain_id |> stored_blocks([block_hash]) |> Enum.any?(&(not &1.canonical))

  @doc """
  Commits one plan under the lease it was made with.

  The lock is retaken, the lease revalidated against database time and the
  cursor revalidated against the exact position the plan was drawn from. Blocks,
  logs, finality promotion and the cursor move land in this single transaction,
  so a rollback advances nothing.
  """
  @spec commit(lease(), tuple(), pos_integer()) :: {:ok, term()} | {:error, term()}
  def commit(lease, plan, bound) do
    Repo.transaction(fn ->
      now = db_now()
      ensure(lease.chain_id, lease.next_block, now)
      cursor = lock(lease.chain_id)

      if held?(cursor, lease, now),
        do: apply_plan(cursor, plan, bound, now),
        else: Repo.rollback(:lease_lost)
    end)
  end

  defp admit(chain_id, address, start_block) do
    ensure(chain_id, start_block, db_now())
    cursor = lock(chain_id)

    case source(chain_id, address) do
      nil -> opened(cursor, chain_id, address, start_block)
      %{start_block: ^start_block} = admitted -> admitted
      _contradicted -> Repo.rollback(:source_start_conflict)
    end
  end

  defp opened(cursor, chain_id, address, start_block) do
    source =
      Ash.create!(
        Source,
        %{chain_id: chain_id, address: address, start_block: start_block},
        action: :admit,
        actor: @actor
      )

    move_to(cursor, min(cursor.next_block_to_fetch, start_block))
    source
  end

  defp claim(cursor, now, lease_ms) do
    if leased?(cursor, now), do: Repo.rollback(:leased), else: grant(cursor, now, lease_ms)
  end

  defp grant(cursor, now, lease_ms) do
    owner = Ash.UUID.generate()

    cursor
    |> Ash.update!(
      %{lease_owner: owner, lease_expires_at: DateTime.add(now, lease_ms, :millisecond)},
      action: :claim_lease,
      actor: @actor
    )
    |> then(&%{chain_id: &1.chain_id, owner: owner, next_block: &1.next_block_to_fetch})
  end

  defp relinquish(%{lease_owner: owner} = cursor, owner),
    do: Ash.update!(cursor, %{}, action: :release_lease, actor: @actor)

  defp relinquish(cursor, _other_owner), do: cursor

  defp leased?(%{lease_expires_at: nil}, _now), do: false
  defp leased?(%{lease_expires_at: expires_at}, now), do: DateTime.after?(expires_at, now)

  defp held?(%{lease_owner: owner, next_block_to_fetch: next} = cursor, lease, now),
    do: owner == lease.owner and next == lease.next_block and leased?(cursor, now)

  defp apply_plan(cursor, {:range, headers, logs, finality}, bound, now) do
    case divergence(cursor.chain_id, headers) do
      # The old suffix goes, the cursor stays: a late source may have pulled it
      # below the divergence, and the next pass stores the new fork from there
      # rather than skipping the blocks that source was admitted for.
      {:forked, height} ->
        orphan(cursor, height - 1, bound)

      :none ->
        blocks = record_blocks(cursor.chain_id, headers, now)
        record_logs(cursor.chain_id, blocks, logs, now)
        promote(cursor.chain_id, finality, bound)
        move_to(cursor, List.last(headers).number + 1)
    end
  end

  defp apply_plan(cursor, {:promote, finality}, bound, _now) do
    promote(cursor.chain_id, finality, bound)
    cursor
  end

  defp apply_plan(cursor, {:rewind, ancestor}, bound, _now),
    do: cursor |> orphan(ancestor, bound) |> move_to(ancestor + 1)

  # What the ledger already knows about the headers just fetched. A stored
  # orphan is never revived, so a provider serving an abandoned fork again fails
  # the pass before anything is written. A canonical row at one of these heights
  # under another hash is the new fork's first divergence.
  defp divergence(chain_id, headers) do
    chain_id
    |> stored_blocks(Enum.map(headers, & &1.hash))
    |> Enum.each(&live/1)

    canonical =
      chain_id
      |> canonical_range(hd(headers).number, List.last(headers).number)
      |> by_key(& &1.block_number)

    Enum.find_value(headers, :none, &forked(canonical, &1))
  end

  defp live(%{canonical: true}), do: :ok
  defp live(orphan), do: Repo.rollback({:noncanonical_replay, orphan.block_number})

  defp forked(canonical, header), do: canonical |> Map.get(header.number) |> diverged(header)

  defp diverged(nil, _header), do: nil
  defp diverged(%{block_hash: hash}, %{hash: hash}), do: nil
  defp diverged(_parted, header), do: {:forked, header.number}

  # Finality is not revisable, so a divergence that reaches a finalized block
  # refuses the whole rewind before a single row is demoted.
  defp orphan(cursor, ancestor, bound) do
    cursor.chain_id |> finalized_head() |> revisable(ancestor)

    cursor.chain_id
    |> orphans(ancestor, bound)
    |> Enum.each(&Ash.update!(&1, %{}, action: :mark_noncanonical, actor: @actor))

    cursor
  end

  defp revisable(%{block_number: number}, ancestor) when number > ancestor,
    do: Repo.rollback({:finalized_rewind, number})

  defp revisable(_finality, _ancestor), do: :ok

  # Insert-only: the identity decides the duplicate race, and every header in the
  # range must then be stored exactly as the provider just described it. A stored
  # orphan is never revived and a stored promotion is never demoted, because no
  # column of an existing row is written here.
  defp record_blocks(chain_id, headers, now) do
    insert_absent(Block, Enum.map(headers, &block_row(chain_id, &1, now)), [
      :chain_id,
      :block_hash
    ])

    stored = by_key(stored_blocks(chain_id, Enum.map(headers, & &1.hash)), & &1.block_hash)
    Enum.each(headers, &verify_block(Map.fetch!(stored, &1.hash), &1))
    stored
  end

  defp verify_block(%{block_number: number, parent_hash: parent}, %{
         number: number,
         parent_hash: parent
       }),
       do: :ok

  defp verify_block(_stored, header), do: Repo.rollback({:block_conflict, header.number})

  defp record_logs(chain_id, blocks, logs, now) do
    insert_absent(Log, Enum.map(logs, &log_row(chain_id, &1, blocks, now)), [
      :chain_id,
      :block_hash,
      :log_index
    ])

    stored =
      chain_id
      |> stored_logs(Map.keys(blocks))
      |> by_key(&{&1.block_hash, &1.log_index})

    Enum.each(logs, &verify_log(Map.fetch!(stored, {&1.block_hash, &1.log_index}), &1))
  end

  defp verify_log(
         %{
           transaction_hash: transaction_hash,
           transaction_index: transaction_index,
           address: address,
           topics: topics,
           data: data
         },
         %{
           transaction_hash: transaction_hash,
           transaction_index: transaction_index,
           address: address,
           topics: topics,
           data: data
         }
       ),
       do: :ok

  defp verify_log(_stored, log), do: Repo.rollback({:log_conflict, log.log_index})

  # Finality is the provider's exact finalized hash matching the canonical block
  # stored at that height; the already validated parent chain beneath it is what
  # makes the bounded batch below it promotable.
  defp promote(chain_id, %{number: number, hash: hash}, bound) do
    if match?(%{block_hash: ^hash}, canonical_block(chain_id, number)),
      do: finalize(chain_id, number, bound)
  end

  defp finalize(chain_id, number, bound) do
    Block
    |> Ash.Query.for_read(:promotable, %{chain_id: chain_id, through_block_number: number})
    |> Ash.Query.limit(bound)
    |> Ash.read!(actor: @actor)
    |> Enum.each(&Ash.update!(&1, %{}, action: :mark_finalized, actor: @actor))
  end

  defp canonical_range(chain_id, from, to) do
    Block
    |> Ash.Query.for_read(:canonical_between, %{
      chain_id: chain_id,
      from_block_number: from,
      to_block_number: to
    })
    |> Ash.read!(actor: @actor)
  end

  defp finalized_head(chain_id) do
    Block
    |> Ash.Query.for_read(:finalized_head, %{chain_id: chain_id})
    |> Ash.read_one!(actor: @actor)
  end

  defp orphans(chain_id, ancestor, bound) do
    Block
    |> Ash.Query.for_read(:canonical_after, %{chain_id: chain_id, block_number: ancestor})
    |> Ash.Query.limit(bound)
    |> Ash.read!(actor: @actor)
  end

  defp stored_blocks(chain_id, hashes) do
    Block
    |> Ash.Query.for_read(:by_hashes, %{chain_id: chain_id, block_hashes: hashes})
    |> Ash.read!(actor: @actor)
  end

  defp source(chain_id, address) do
    Source
    |> Ash.Query.for_read(:for_address, %{chain_id: chain_id, address: address})
    |> Ash.read_one!(actor: @actor)
  end

  defp stored_logs(chain_id, hashes) do
    Log
    |> Ash.Query.for_read(:by_block_hashes, %{chain_id: chain_id, block_hashes: hashes})
    |> Ash.read!(actor: @actor)
  end

  defp block_row(chain_id, header, now) do
    %{
      id: Ash.UUID.generate(),
      chain_id: chain_id,
      block_number: header.number,
      block_hash: header.hash,
      parent_hash: header.parent_hash,
      canonical: true,
      finalized: false,
      inserted_at: now,
      updated_at: now
    }
  end

  defp log_row(chain_id, log, blocks, now) do
    %{
      id: Ash.UUID.generate(),
      chain_id: chain_id,
      block_id: Map.fetch!(blocks, log.block_hash).id,
      block_hash: log.block_hash,
      log_index: log.log_index,
      transaction_hash: log.transaction_hash,
      transaction_index: log.transaction_index,
      address: log.address,
      topics: log.topics,
      data: log.data,
      inserted_at: now,
      updated_at: now
    }
  end

  defp move_to(%{next_block_to_fetch: block} = cursor, block), do: cursor

  defp move_to(cursor, block),
    do: Ash.update!(cursor, %{next_block_to_fetch: block}, action: :move_to, actor: @actor)

  # Admission and every commit insert-if-absent before locking, so the
  # absent-row order of a race takes the same lock as the present-row one.
  defp ensure(chain_id, next_block_to_fetch, now) do
    insert_absent(
      Cursor,
      [
        %{
          id: Ash.UUID.generate(),
          chain_id: chain_id,
          next_block_to_fetch: next_block_to_fetch,
          inserted_at: now,
          updated_at: now
        }
      ],
      [:chain_id]
    )
  end

  # The identity's unique index decides every duplicate race; nothing already
  # stored is rewritten, so a replay can only confirm or contradict evidence.
  defp insert_absent(resource, rows, conflict_target) do
    Repo.insert_all(resource, rows,
      prefix: AshPostgres.DataLayer.Info.schema(resource),
      on_conflict: :nothing,
      conflict_target: conflict_target
    )
  end

  defp lock(chain_id) do
    Cursor
    |> Ash.Query.for_read(:for_chain, %{chain_id: chain_id})
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one!(actor: @actor)
  end

  defp by_key(records, key), do: Map.new(records, &{key.(&1), &1})

  # Lease expiry and every stored timestamp are measured by the database, so a
  # skewed application clock cannot extend or shorten an owner's window.
  defp db_now do
    %{rows: [[now]]} = Repo.query!("SELECT now()")
    now
  end
end
