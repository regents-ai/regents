defmodule AshPlatform.WalletActions.StakeRedeemOperationTest do
  @moduledoc """
  What the durable operation row guarantees for Stake and Redeem.

  The concurrency proofs run on real second connections and let PostgreSQL
  report the ordering through `pg_blocking_pids`, so no clock decides a race.
  Those tests commit outside the sandbox, so the whole file clears committed
  operations before and after every test: the unique submitted-hash identities
  make this suite order-dependent otherwise, and a crashed run would poison the
  next one.
  """

  use AshPlatformWeb.ConnCase, async: false

  import Ecto.Query

  alias AshPlatform.Accounts
  alias AshPlatform.Accounts.SessionAuthority
  alias AshPlatform.Actors.System
  alias AshPlatform.{Redemption, Repo, Staking}
  alias AshPlatform.WalletActions.{StakeRedeemOperation, StakeRedeemOperations}

  @wallet "0x1111111111111111111111111111111111111111"
  @action_hash "0x" <> String.duplicate("ab", 32)
  @other_hash "0x" <> String.duplicate("ef", 32)

  setup :clear_committed_operations

  test "CLAIM_BEFORE_WALLET_HANDOFF: prepare, claim, bind, receipt and confirm are one durable path" do
    {account, lease, envelope} = prepared("path")

    assert {:ok, operation} = active(account.id)
    assert operation.state == :prepared
    assert operation.action_id == envelope.action_id
    assert operation.capability == :stake
    assert operation.human_account_id == account.id

    assert {:ok, claimed} = claim(lease, envelope, :action)
    assert claimed.state == :action_dispatched

    assert {:ok, bound} = bind(lease, envelope, :action, @action_hash)
    assert bound.state == :action_submitted
    assert bound.action_transaction_hash == @action_hash

    assert {:ok, _receipted} =
             StakeRedeemOperations.record_receipt(lease, :stake, envelope.action_id, :action)

    assert {:ok, confirmed} = StakeRedeemOperations.confirm(lease, :stake, envelope.action_id)
    assert confirmed.state == :confirmed
    refute is_nil(confirmed.action_receipt_at)
    refute is_nil(confirmed.action_reread_at)
    refute is_nil(confirmed.terminal_at)

    # A terminal operation releases the account's single active slot.
    assert {:ok, nil} = active(account.id)
  end

  test "CLAIM_BEFORE_WALLET_HANDOFF: a claimed dispatch cannot be claimed a second time" do
    {_account, lease, envelope} = prepared("second-claim")

    assert {:ok, _claimed} = claim(lease, envelope, :action)
    assert {:error, _refused} = claim(lease, envelope, :action)
  end

  test "CLAIM_BEFORE_WALLET_HANDOFF: only the exact rejected phase closes a hash-free dispatch" do
    {_account, lease, envelope} = prepared("phase-rejection")

    assert {:ok, _claimed} = claim(lease, envelope, :action)

    assert {:error, :rejection_phase_mismatch} =
             StakeRedeemOperations.close_not_sent(
               lease,
               :stake,
               envelope.action_id,
               :approval,
               "rejected"
             )

    assert {:ok, closed} =
             StakeRedeemOperations.close_not_sent(
               lease,
               :stake,
               envelope.action_id,
               :action,
               "rejected"
             )

    assert closed.state == :not_sent
  end

  test "CLAIM_BEFORE_WALLET_HANDOFF: a dispatch that bound a hash can never be closed as unsent" do
    {_account, lease, envelope} = prepared("sent-not-unsent")

    assert {:ok, _claimed} = claim(lease, envelope, :action)
    assert {:ok, _bound} = bind(lease, envelope, :action, @action_hash)

    assert {:error, :rejection_phase_mismatch} =
             StakeRedeemOperations.close_not_sent(
               lease,
               :stake,
               envelope.action_id,
               :action,
               "rejected"
             )
  end

  test "EXACT_SUBMITTED_IDENTITY_SURVIVES: the first hash binds, an exact replay is a no-op, a different hash is refused" do
    {_account, lease, envelope} = prepared("hash-identity")

    assert {:ok, _claimed} = claim(lease, envelope, :action)
    assert {:ok, bound} = bind(lease, envelope, :action, @action_hash)
    assert bound.action_transaction_hash == @action_hash

    assert {:ok, replayed} = bind(lease, envelope, :action, "0x" <> String.duplicate("AB", 32))
    assert replayed.action_transaction_hash == @action_hash
    assert replayed.state == :action_submitted

    assert {:error, :submitted_hash_conflict} = bind(lease, envelope, :action, @other_hash)
    assert {:error, :invalid_hash} = bind(lease, envelope, :action, "0xnope")
  end

  test "REJECTION_WRITES_NOTHING: a malformed hash leaves the claimed dispatch exactly as it was" do
    {account, lease, envelope} = prepared("malformed-hash")

    assert {:ok, claimed} = claim(lease, envelope, :action)
    assert claimed.state == :action_dispatched

    assert {:error, :invalid_hash} =
             bind(lease, envelope, :action, "0x" <> String.duplicate("a", 63) <> "\n")

    assert {:error, :invalid_hash} =
             bind(lease, envelope, :action, "0X" <> String.duplicate("ab", 32))

    assert {:ok,
            %{
              state: :action_dispatched,
              approval_transaction_hash: nil,
              action_transaction_hash: nil,
              action_receipt_at: nil,
              action_reread_at: nil,
              terminal_at: nil
            }} = active(account.id)
  end

  test "RECEIPT_AND_REREAD_BOTH_REQUIRED: a receipt without a reread never reaches confirmed" do
    {_account, lease, envelope} = prepared("receipt-only")

    assert {:ok, _claimed} = claim(lease, envelope, :action)
    assert {:ok, _bound} = bind(lease, envelope, :action, @action_hash)

    assert {:ok, receipted} =
             StakeRedeemOperations.record_receipt(lease, :stake, envelope.action_id, :action)

    assert receipted.state == :action_submitted
    refute is_nil(receipted.action_receipt_at)
    assert is_nil(receipted.action_reread_at)
    assert is_nil(receipted.terminal_at)
  end

  test "RECEIPT_AND_REREAD_BOTH_REQUIRED: confirmation refuses a hash whose receipt was never recorded" do
    {_account, lease, envelope} = prepared("no-receipt")

    assert {:ok, _claimed} = claim(lease, envelope, :action)
    assert {:ok, _bound} = bind(lease, envelope, :action, @action_hash)
    assert {:error, _refused} = StakeRedeemOperations.confirm(lease, :stake, envelope.action_id)
  end

  test "STAKE_APPROVAL_MEANS_ALLOWANCE: the action phase is unclaimable until the approval is verified" do
    {_account, lease, envelope} = prepared("approval-gate")

    assert {:ok, _claimed} = claim(lease, envelope, :approval)
    assert {:error, _refused} = claim(lease, envelope, :action)

    assert {:ok, _bound} = bind(lease, envelope, :approval, @action_hash)
    assert {:error, _refused} = claim(lease, envelope, :action)

    assert {:ok, _receipted} =
             StakeRedeemOperations.record_receipt(lease, :stake, envelope.action_id, :approval)

    assert {:ok, verified} =
             StakeRedeemOperations.verify_approval(lease, :stake, envelope.action_id)

    assert verified.state == :approval_verified
    assert {:ok, claimed} = claim(lease, envelope, :action)
    assert claimed.state == :action_dispatched
  end

  test "DATABASE_DECIDES_THE_RACE: only an undispatched review or a verified approval is withdrawable" do
    {_account, lease, envelope} = prepared("withdraw")

    assert {:ok, _claimed} = claim(lease, envelope, :approval)
    assert {:error, _hashless} = cancel(lease, envelope)

    assert {:ok, _bound} = bind(lease, envelope, :approval, @action_hash)
    assert {:error, _unverified} = cancel(lease, envelope)

    assert {:ok, _receipted} =
             StakeRedeemOperations.record_receipt(lease, :stake, envelope.action_id, :approval)

    assert {:ok, _verified} =
             StakeRedeemOperations.verify_approval(lease, :stake, envelope.action_id)

    assert {:ok, cancelled} = cancel(lease, envelope)
    assert cancelled.state == :cancelled
    refute is_nil(cancelled.terminal_at)
  end

  test "DATABASE_DECIDES_THE_RACE: a claimed action can never be withdrawn" do
    {_account, lease, envelope} = prepared("withdraw-action")

    assert {:ok, _claimed} = claim(lease, envelope, :action)
    assert {:error, _claimed_action} = cancel(lease, envelope)

    assert {:ok, _bound} = bind(lease, envelope, :action, @action_hash)
    assert {:error, _submitted_action} = cancel(lease, envelope)
  end

  test "DATABASE_DECIDES_THE_RACE: one account holds one active operation per capability" do
    {account, lease, first} = prepared("one-active")

    # A review nobody dispatched is replaced by the next review.
    {:ok, second} = Staking.prepare_unstake(@wallet, "1", leased(account.id))
    assert {:ok, %{action_id: action_id}} = active(account.id)
    assert action_id == second.action_id
    refute second.action_id == first.action_id

    # Once dispatched, the slot is held until the operation reaches a terminal state.
    assert {:ok, _claimed} = claim(lease, second, :action)
    assert {:error, _in_flight} = Staking.prepare_stake(@wallet, "1", leased(account.id))
  end

  test "DATABASE_DECIDES_THE_RACE: Stake and Redeem hold separate active slots" do
    {account, lease, stake} = prepared("separate-capabilities")
    assert {:ok, _claimed} = claim(lease, stake, :action)

    assert {:ok, redeem} = Redemption.prepare_claim(@wallet, leased(account.id))
    assert {:ok, %{capability: :redeem}} = StakeRedeemOperations.active(account.id, :redeem)
    assert {:ok, %{capability: :stake}} = active(account.id)
    refute redeem.action_id == stake.action_id
  end

  test "CURRENT_AUTHORITY_OWNS_EVERY_WRITE: a revoked lineage writes nothing" do
    {_account, lease, envelope} = prepared("revoked")

    SessionAuthority.revoke(%{lineage: lease.lineage})

    assert {:error, :stale_authority} = claim(lease, envelope, :action)
    assert {:ok, %{state: :prepared}} = StakeRedeemOperations.active(lease.account_id, :stake)
  end

  test "CURRENT_AUTHORITY_OWNS_EVERY_WRITE: a failing callback rolls its whole transition back" do
    {_account, lease, envelope} = prepared("rollback")

    assert {:ok, _claimed} = claim(lease, envelope, :action)
    assert {:ok, _bound} = bind(lease, envelope, :action, @action_hash)

    # The receipt is missing, so `confirm` refuses and nothing about the row moves.
    assert {:error, _refused} = StakeRedeemOperations.confirm(lease, :stake, envelope.action_id)
    assert {:ok, unchanged} = StakeRedeemOperations.active(lease.account_id, :stake)
    assert unchanged.state == :action_submitted
    assert is_nil(unchanged.action_reread_at)
    assert is_nil(unchanged.terminal_at)
  end

  describe "on real second connections" do
    test "DATABASE_DECIDES_THE_RACE: two sockets racing one dispatch produce exactly one winner" do
      {_account, lease, envelope} = unboxed(fn -> committed_preparation("race-dispatch") end)

      winner = holding(fn -> claim(lease, envelope, :action) end)
      rival = contending(fn -> claim(lease, envelope, :action) end)

      assert_blocked_by(rival, winner)
      assert {:ok, claimed} = release(winner)
      assert claimed.state == :action_dispatched

      # The loser took the row lock second, saw a state that was no longer
      # claimable, and wrote nothing.
      assert {:error, _refused} = settled(rival)

      assert unboxed(fn -> active(lease.account_id) end) |> elem(1) |> Map.get(:state) ==
               :action_dispatched
    end

    test "BARRIER_AND_RESTART_PROOF: a logout that commits before a write leaves the write refused" do
      {_account, lease, envelope} = unboxed(fn -> committed_preparation("logout-first") end)

      unboxed(fn -> SessionAuthority.revoke(%{lineage: lease.lineage}) end)

      assert unboxed(fn -> claim(lease, envelope, :action) end) == {:error, :stale_authority}

      assert unboxed(fn -> active(lease.account_id) end) |> elem(1) |> Map.get(:state) ==
               :prepared
    end

    test "BARRIER_AND_RESTART_PROOF: a logout contending behind a write waits for it and does not undo it" do
      {_account, lease, envelope} = unboxed(fn -> committed_preparation("write-first") end)

      writer = holding(fn -> claim(lease, envelope, :action) end)
      logout = contending(fn -> SessionAuthority.revoke(%{lineage: lease.lineage}) end)

      assert_blocked_by(logout, writer)
      assert {:ok, claimed} = release(writer)
      assert claimed.state == :action_dispatched
      assert settled(logout)

      # The committed claim survives the revocation that ordered behind it, and
      # the lineage can no longer authorize anything further.
      assert unboxed(fn -> active(lease.account_id) end) |> elem(1) |> Map.get(:state) ==
               :action_dispatched

      assert unboxed(fn -> bind(lease, envelope, :action, @action_hash) end) ==
               {:error, :stale_authority}
    end
  end

  ## Sandbox setup

  defp prepared(seed) do
    account = register(seed)
    opts = leased(account.id)
    {:ok, envelope} = Staking.prepare_stake(@wallet, "1", opts)
    {account, opts[:context].session_lease, envelope}
  end

  defp register(seed) do
    {:ok, account} =
      Accounts.register_verified("did:privy:operation-#{seed}", @wallet, [@wallet],
        actor: %System{}
      )

    account
  end

  defp active(account_id), do: StakeRedeemOperations.active(account_id, :stake)

  defp claim(lease, envelope, phase),
    do: StakeRedeemOperations.claim_dispatch(lease, :stake, envelope.action_id, phase)

  defp bind(lease, envelope, phase, hash),
    do: StakeRedeemOperations.bind_hash(lease, :stake, envelope.action_id, phase, hash)

  defp cancel(lease, envelope),
    do: StakeRedeemOperations.cancel(lease, :stake, envelope.action_id, "withdrawn")

  ## Committed setup and barriers for the second-connection proofs

  defp committed_preparation(seed) do
    account = register(seed)
    opts = leased(account.id)
    {:ok, envelope} = Staking.prepare_stake(@wallet, "1", opts)
    {account, opts[:context].session_lease, envelope}
  end

  # Committed operations outlive the sandbox, so they are cleared for every test
  # rather than only around the ones that mint them, dependent rows first.
  defp clear_committed_operations(_context) do
    remove = fn ->
      Repo.delete_all(StakeRedeemOperation)
      Repo.delete_all(from(row in SessionAuthority, where: not is_nil(row.human_account_id)))

      Repo.delete_all(
        from(account in Accounts.HumanAccount,
          prefix: "platform",
          where: like(account.privy_user_id, "did:privy:operation-%")
        )
      )
    end

    unboxed(remove)
    on_exit(fn -> unboxed(remove) end)
  end

  defp unboxed(attempt), do: Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, attempt)

  defp holding(attempt) do
    test = self()
    task = Task.async(fn -> unboxed(fn -> hold(attempt, test) end) end)
    assert_receive {:holding, holder, backend}, 5_000
    {task, holder, backend}
  end

  defp release({task, holder, _backend}) do
    send(holder, :release)
    {:ok, result} = Task.await(task, 15_000)
    result
  end

  defp contending(attempt) do
    test = self()

    task =
      Task.async(fn ->
        unboxed(fn ->
          send(test, {:contending, backend_pid()})
          send(test, {:settled, attempt.()})
        end)
      end)

    assert_receive {:contending, backend}, 5_000
    {task, backend}
  end

  defp settled({task, _backend}) do
    assert_receive {:settled, result}, 15_000
    Task.await(task, 15_000)
    result
  end

  # PostgreSQL itself reports the ordering, so no sleep decides the race.
  defp assert_blocked_by({_rival_task, contender}, {_holder_task, _holder, holder_backend}) do
    assert Enum.reduce_while(1..2_000, false, fn _attempt, _blocked ->
             if holder_backend in blocking_pids(contender),
               do: {:halt, true},
               else: {:cont, false}
           end),
           "the contender never blocked on the held operation row"
  end

  defp blocking_pids(backend) do
    unboxed(fn ->
      %{rows: [[blockers]]} = Repo.query!("SELECT pg_blocking_pids($1)", [backend])
      blockers
    end)
  end

  defp backend_pid do
    %{rows: [[backend]]} = Repo.query!("SELECT pg_backend_pid()")
    backend
  end

  defp hold(attempt, test) do
    Repo.transaction(fn ->
      result = attempt.()
      send(test, {:holding, self(), backend_pid()})

      receive do
        :release -> result
      after
        15_000 -> result
      end
    end)
  end
end
