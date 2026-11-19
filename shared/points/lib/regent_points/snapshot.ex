defmodule RegentPoints.Snapshot do
  @moduledoc "Period-end chain and account evidence. Missing historical evidence always refuses a tally."
  require Ash.Query
  alias RegentPoints.{Nfts, PeriodSnapshot, Rules, Store, WalletCoverage}

  def for_period(program, period, now \\ DateTime.utc_now())

  def for_period(program, period, now) when is_integer(period) and period > 0 do
    with %DateTime{} = start <- Rules.config()[:starts_at],
         true <- program == Rules.program(),
         {from, stop} <- Rules.period(period),
         true <- DateTime.compare(stop, now) != :gt,
         [coverage] <- Ash.read!(WalletCoverage, actor: Store.system()),
         true <- DateTime.compare(start, coverage.starts_at) != :lt do
      query = Ash.Query.filter(PeriodSnapshot, program_id == ^program and period == ^period)

      with {:ok, saved} <- Ash.read_one(query, actor: Store.system()),
           {:ok, snapshot} <- saved_or_record(saved, program, period, from, stop),
           true <-
             DateTime.compare(snapshot.starts_at, from) == :eq and
               DateTime.compare(snapshot.ends_at, stop) == :eq do
        {:ok, snapshot}
      else
        false -> {:error, :snapshot_period_changed}
        {:error, _} = error -> error
      end
    else
      _ -> {:error, :snapshot_not_ready}
    end
  end

  def for_period(_program, _period, _now), do: {:error, :invalid_period}

  defp saved_or_record(nil, program, period, from, stop) do
    with {:ok, block} <- Nfts.period_end_block(stop) do
      # Finish any pre-cutoff wallet writes before freezing the snapshot. All
      # later inserts use the DB clock, which is now past the cutoff. The RPC
      # above runs before this short transaction and never holds a database lock.
      Ash.transact(PeriodSnapshot, fn ->
        RegentPoints.repo(nil, :read).query!(
          "LOCK TABLE regent_points.wallet_snapshots IN SHARE ROW EXCLUSIVE MODE"
        )

        query = Ash.Query.filter(PeriodSnapshot, program_id == ^program and period == ^period)

        case Ash.read_one!(query, actor: Store.system()) do
          nil ->
            PeriodSnapshot
            |> Ash.Changeset.for_create(
              :record,
              %{
                program_id: program,
                period: period,
                starts_at: from,
                ends_at: stop,
                block_number: block.number,
                block_hash: block.hash,
                block_at: block.at
              },
              actor: Store.system()
            )
            |> Ash.create!()

          saved ->
            saved
        end
      end)
    end
  end

  defp saved_or_record(snapshot, _program, _period, _from, _stop), do: {:ok, snapshot}

  @doc "The account's verified wallets immediately before period end, refusing ambiguous ownership."
  def wallets(account_id, snapshot) do
    # Choose the last version of EVERY account before testing overlap. Filtering
    # versions by address first would resurrect a wallet that was later removed.
    sql = """
    WITH latest AS (
      SELECT DISTINCT ON (account_id) account_id, wallet_addresses
      FROM regent_points.wallet_snapshots WHERE effective_at < $1
      ORDER BY account_id, effective_at DESC, id DESC
    )
    SELECT account_id, wallet_addresses FROM latest
    WHERE account_id = $2 OR wallet_addresses &&
      (SELECT wallet_addresses FROM latest WHERE account_id = $2)
    """

    with {:ok, %{rows: rows}} <-
           RegentPoints.repo(nil, :read).query(sql, [
             DateTime.to_naive(snapshot.ends_at),
             account_id
           ]) do
      case rows do
        [] -> {:ok, []}
        [[^account_id, wallets]] -> {:ok, wallets}
        _ambiguous -> {:error, :ambiguous_snapshot_wallet}
      end
    end
  end
end
