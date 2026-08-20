defmodule AshPlatform.Autolaunch.BidOperationTest do
  use AshPlatformWeb.ConnCase, async: false

  import AshPlatform.BidFixture

  alias AshPlatform.Accounts.SessionAuthority
  alias AshPlatform.Autolaunch
  alias AshPlatform.TestAutolaunchBidChainClient, as: Chain

  @approval_hash "0x" <> String.duplicate("aa", 32)
  @permit2_hash "0x" <> String.duplicate("bb", 32)
  @bid_hash "0x" <> String.duplicate("cc", 32)
  @other_hash "0x" <> String.duplicate("dd", 32)

  setup :bidder

  setup do
    install()
    :ok
  end

  test "ORDERED_SINGLE_SEND: each step binds its own hash before the next becomes sendable", %{
    auction: auction,
    wallet: wallet,
    opts: opts
  } do
    operation = review(auction, wallet, opts)
    assert {operation.step, operation.state} == {:token_approval, :prepared}

    operation = confirm_step(operation, :token_approval, @approval_hash, opts)
    assert {operation.step, operation.state} == {:permit2_approval, :prepared}
    assert operation.token_approval_transaction_hash == @approval_hash

    operation = confirm_step(operation, :permit2_approval, @permit2_hash, opts)
    assert {operation.step, operation.state} == {:bid, :prepared}
    assert operation.permit2_approval_transaction_hash == @permit2_hash

    Chain.put(%{outcomes: %{bid: %{outcome: :confirmed, onchain_bid_id: "42"}}})
    operation = confirm_step(operation, :bid, @bid_hash, opts)

    assert operation.state == :confirmed
    assert operation.onchain_bid_id == "42"
    assert operation.bid_transaction_hash == @bid_hash
    assert operation.terminal_at

    # The confirmed bid released the account's open slot.
    assert {:ok, %{operation: nil}} = Autolaunch.open_bid_operation(opts)
  end

  test "BID_ID_IS_ADOPTED_FROM_THE_EVENT: a receipt contradicting the review never confirms", %{
    auction: auction,
    wallet: wallet,
    opts: opts
  } do
    operation = sendable_bid(auction, wallet, opts)

    Chain.put(%{outcomes: %{bid: %{outcome: :unverified}}})
    operation = confirm_step(operation, :bid, @bid_hash, opts)

    assert operation.state == :unverified
    assert is_nil(operation.onchain_bid_id)
    assert operation.terminal_at
  end

  test "A_REVERT_IS_NEVER_SUCCESS: a canonical revert ends the operation", %{
    auction: auction,
    wallet: wallet,
    opts: opts
  } do
    operation = sendable_bid(auction, wallet, opts)

    Chain.put(%{outcomes: %{bid: %{outcome: :reverted}}})
    operation = confirm_step(operation, :bid, @bid_hash, opts)

    assert operation.state == :reverted
    assert operation.terminal_at
  end

  test "PENDING_WRITES_NOTHING: an unresolved hash stays bound and readable again", %{
    auction: auction,
    wallet: wallet,
    opts: opts
  } do
    operation = auction |> sendable_bid(wallet, opts) |> submitted(@bid_hash, opts)

    Chain.put(%{outcomes: %{}})
    {:ok, %{operation: pending}} = Autolaunch.verify_bid_step(operation.action_id, opts)

    assert pending.state == :submitted
    assert pending.bid_transaction_hash == @bid_hash
    assert is_nil(pending.terminal_at)

    Chain.put(%{outcomes: %{bid: %{outcome: :confirmed, onchain_bid_id: "7"}}})
    {:ok, %{operation: settled}} = Autolaunch.verify_bid_step(operation.action_id, opts)
    assert {settled.state, settled.onchain_bid_id} == {:confirmed, "7"}
  end

  test "NO_PROVIDER_READ_UNDER_A_LOCK: the bound hash is read before the lease transaction opens",
       %{auction: auction, wallet: wallet, opts: opts} do
    operation = submitted(review(auction, wallet, opts), @approval_hash, opts)

    Chain.put(%{outcomes: %{token_approval: %{outcome: :confirmed}}})

    assert {:ok, %{operation: settled}} = Autolaunch.verify_bid_step(operation.action_id, opts)
    assert {settled.step, settled.state} == {:permit2_approval, :prepared}
    refute Chain.state().read_in_transaction?
  end

  test "A_RECEIPT_NEVER_SETTLES_A_ROW_THAT_MOVED: a candidate raced mid-read applies nothing", %{
    auction: auction,
    wallet: wallet,
    opts: opts
  } do
    operation = submitted(review(auction, wallet, opts), @approval_hash, opts)

    Chain.put(%{
      outcomes: %{token_approval: %{outcome: :confirmed}},
      raced: fn -> Autolaunch.start_new_bid(operation.action_id, opts) end
    })

    assert {:ok, %{operation: unmoved}} = Autolaunch.verify_bid_step(operation.action_id, opts)
    assert {unmoved.step, unmoved.state} == {:token_approval, :submission_unknown}
    assert unmoved.token_approval_transaction_hash == @approval_hash
  end

  test "CLAIMED_STEPS_NEVER_RESEND: a duplicate hash replays and a different one is refused", %{
    auction: auction,
    wallet: wallet,
    opts: opts
  } do
    operation = review(auction, wallet, opts)
    {:ok, %{operation: operation}} = Autolaunch.claim_bid_dispatch(operation.action_id, opts)

    assert {:ok, %{operation: bound}} =
             Autolaunch.bind_bid_hash(operation.action_id, @approval_hash, opts)

    assert bound.state == :submitted

    assert {:ok, %{operation: replayed}} =
             Autolaunch.bind_bid_hash(operation.action_id, mixed_case(@approval_hash), opts)

    assert replayed.token_approval_transaction_hash == @approval_hash

    assert {:error, error} = Autolaunch.bind_bid_hash(operation.action_id, @other_hash, opts)
    assert refusal(error) == :submitted_hash_conflict

    # A claimed and submitted step is never offered a second dispatch.
    assert {:error, _claimed} = Autolaunch.claim_bid_dispatch(operation.action_id, opts)
  end

  test "ONE_OPEN_BID_PER_ACCOUNT: an undispatched review is replaced, a claimed one blocks", %{
    auction: auction,
    wallet: wallet,
    opts: opts
  } do
    first = review(auction, wallet, opts)
    second = review(auction, wallet, opts)
    refute second.action_id == first.action_id

    {:ok, %{operation: second}} = Autolaunch.claim_bid_dispatch(second.action_id, opts)
    assert second.state == :dispatched

    assert {:error, error} = Autolaunch.prepare_bid(auction.id, wallet, "1", "3", opts)
    assert refusal(error) == :bid_in_flight
  end

  test "AN_UNKNOWN_CLAIM_NEVER_RESENDS: start-new-bid ends it without touching its calldata", %{
    auction: auction,
    wallet: wallet,
    opts: opts
  } do
    operation = review(auction, wallet, opts)
    {:ok, %{operation: claimed}} = Autolaunch.claim_bid_dispatch(operation.action_id, opts)

    {:ok, %{operation: ended}} = Autolaunch.start_new_bid(claimed.action_id, opts)
    assert ended.state == :submission_unknown
    assert ended.terminal_at
    assert ended.envelope == operation.envelope
    assert is_nil(ended.token_approval_transaction_hash)

    # The slot is released, so a new review is a new bid.
    assert {:ok, %{operation: fresh}} = Autolaunch.prepare_bid(auction.id, wallet, "1", "3", opts)
    refute fresh.action_id == operation.action_id
  end

  test "A_LATE_HASH_NEVER_REOPENS: it attaches to the operation it belongs to", %{
    auction: auction,
    wallet: wallet,
    opts: opts
  } do
    operation = review(auction, wallet, opts)
    {:ok, %{operation: claimed}} = Autolaunch.claim_bid_dispatch(operation.action_id, opts)
    {:ok, %{operation: ended}} = Autolaunch.start_new_bid(claimed.action_id, opts)

    assert {:ok, %{operation: attached}} =
             Autolaunch.bind_bid_hash(ended.action_id, @approval_hash, opts)

    assert attached.token_approval_transaction_hash == @approval_hash
    assert attached.state == :submission_unknown
    assert attached.terminal_at == ended.terminal_at
  end

  test "AN_EXPLICIT_REJECTION_ENDS_A_CLAIM: nothing was sent and nothing is bound", %{
    auction: auction,
    wallet: wallet,
    opts: opts
  } do
    operation = review(auction, wallet, opts)
    {:ok, %{operation: claimed}} = Autolaunch.claim_bid_dispatch(operation.action_id, opts)

    {:ok, %{operation: closed}} = Autolaunch.close_bid_not_sent(claimed.action_id, opts)
    assert closed.state == :not_sent
    assert closed.terminal_at
  end

  test "A_PROVEN_NON_START_RELEASES: the same review becomes sendable again", %{
    auction: auction,
    wallet: wallet,
    opts: opts
  } do
    operation = review(auction, wallet, opts)
    {:ok, %{operation: claimed}} = Autolaunch.claim_bid_dispatch(operation.action_id, opts)

    {:ok, %{operation: released}} =
      Autolaunch.release_unstarted_bid_dispatch(claimed.action_id, opts)

    assert released.state == :prepared

    assert {:ok, %{operation: %{state: :dispatched}}} =
             Autolaunch.claim_bid_dispatch(released.action_id, opts)
  end

  test "AN_UNDISPATCHED_REVIEW_MAY_BE_WITHDRAWN: a started one may not", %{
    auction: auction,
    wallet: wallet,
    opts: opts
  } do
    operation = review(auction, wallet, opts)
    {:ok, %{operation: cancelled}} = Autolaunch.cancel_bid_review(operation.action_id, opts)
    assert cancelled.state == :cancelled

    started = confirm_step(review(auction, wallet, opts), :token_approval, @approval_hash, opts)
    {:ok, %{operation: claimed}} = Autolaunch.claim_bid_dispatch(started.action_id, opts)
    assert {:error, _claimed} = Autolaunch.cancel_bid_review(claimed.action_id, opts)
  end

  test "EXPIRED_PERMIT2_WORK_IS_TERMINAL: recovery ends it and a new review rereads state", %{
    auction: auction,
    wallet: wallet,
    opts: opts
  } do
    operation = confirm_step(review(auction, wallet, opts), :token_approval, @approval_hash, opts)
    assert operation.step == :permit2_approval

    {:ok, expires_at, _offset} =
      DateTime.from_iso8601(operation.envelope["arguments"]["permit2_expires_at"])

    freeze(DateTime.add(expires_at, 1, :second))

    assert {:ok, %{operation: %{state: :expired} = expired}} =
             Autolaunch.claim_bid_dispatch(operation.action_id, opts)

    assert expired.terminal_at
    assert expired.token_approval_transaction_hash == @approval_hash
    assert {:ok, %{operation: nil}} = Autolaunch.open_bid_operation(opts)

    assert {:ok, %{operation: fresh}} = Autolaunch.prepare_bid(auction.id, wallet, "1", "3", opts)
    refute fresh.action_id == operation.action_id
    assert fresh.state == :prepared
  end

  test "RELOAD_RECOVERS_THE_ROW: browser storage restores nothing of its own", %{
    auction: auction,
    wallet: wallet,
    opts: opts
  } do
    operation = review(auction, wallet, opts)
    {:ok, %{operation: claimed}} = Autolaunch.claim_bid_dispatch(operation.action_id, opts)

    assert {:ok, %{operation: recovered}} = Autolaunch.open_bid_operation(opts)
    assert recovered.action_id == claimed.action_id
    assert recovered.state == :dispatched
    assert recovered.signer == wallet
  end

  test "REVOCATION_ENDS_EVERY_WRITE: a revoked lease claims, binds and settles nothing", %{
    auction: auction,
    wallet: wallet,
    opts: opts,
    account: account
  } do
    operation = review(auction, wallet, opts)
    assert SessionAuthority.revoke(%{lineage: opts[:context].session_lease.lineage})

    for refused <- [
          fn -> Autolaunch.claim_bid_dispatch(operation.action_id, opts) end,
          fn -> Autolaunch.bind_bid_hash(operation.action_id, @approval_hash, opts) end,
          fn -> Autolaunch.verify_bid_step(operation.action_id, opts) end,
          fn -> Autolaunch.cancel_bid_review(operation.action_id, opts) end,
          fn -> Autolaunch.prepare_bid(auction.id, wallet, "1", "3", opts) end
        ] do
      assert {:error, error} = refused.()
      assert refusal(error) == :session_unavailable
    end

    # The row the revoked session left is untouched and still that account's.
    {:ok, :bind, claim} = SessionAuthority.sign_in(SessionAuthority.bootstrap(), account.id)

    reauthenticated =
      Keyword.put(opts, :context, %{
        session_lease: %{lineage: claim.lineage, account_id: account.id}
      })

    assert {:ok, %{operation: %{state: :prepared, action_id: action_id}}} =
             Autolaunch.open_bid_operation(reauthenticated)

    assert action_id == operation.action_id
  end

  defp review(auction, wallet, opts) do
    {:ok, %{operation: operation}} = Autolaunch.prepare_bid(auction.id, wallet, "1", "3", opts)
    operation
  end

  defp sendable_bid(auction, wallet, opts) do
    auction
    |> review(wallet, opts)
    |> confirm_step(:token_approval, @approval_hash, opts)
    |> confirm_step(:permit2_approval, @permit2_hash, opts)
  end

  defp confirm_step(operation, step, hash, opts) do
    Chain.put(%{outcomes: Map.put_new(Chain.state().outcomes, step, %{outcome: :confirmed})})
    submitted(operation, hash, opts)
    {:ok, %{operation: settled}} = Autolaunch.verify_bid_step(operation.action_id, opts)
    settled
  end

  defp submitted(operation, hash, opts) do
    {:ok, %{operation: _claimed}} = Autolaunch.claim_bid_dispatch(operation.action_id, opts)
    {:ok, %{operation: bound}} = Autolaunch.bind_bid_hash(operation.action_id, hash, opts)
    bound
  end

  defp freeze(instant) do
    previous = Application.get_env(:ash_platform, :wallet_action_clock)
    Application.put_env(:ash_platform, :wallet_action_clock, fn -> instant end)
    on_exit(fn -> restore(:wallet_action_clock, previous) end)
  end

  defp mixed_case("0x" <> hash), do: "0x" <> String.upcase(hash)

  defp restore(key, nil), do: Application.delete_env(:ash_platform, key)
  defp restore(key, value), do: Application.put_env(:ash_platform, key, value)
end
