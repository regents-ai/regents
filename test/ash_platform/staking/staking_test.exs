defmodule AshPlatform.StakingTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.{Accounts, Staking}
  alias AshPlatform.Accounts.SessionAuthority
  alias AshPlatform.Actors.{Human, System}
  alias AshPlatform.WalletActions.Envelope

  @wallet "0x1111111111111111111111111111111111111111"
  @other "0x2222222222222222222222222222222222222222"

  defmodule ChainStub do
    @behaviour AshPlatform.Staking.ChainClient

    @public %{
      chain_id: 8453,
      chain_label: "Base",
      block_number: 42,
      block_hash: "0x" <> String.duplicate("1b", 32),
      contract_address: "0xb027dc261636e30cbc0fe25b2f8e1ed273354ab5",
      paused: false,
      total_staked: "100",
      total_staked_raw: "100000000000000000000",
      supply_denominator_raw: "1000000000000000000000"
    }
    @position %{
      wallet_token_balance_raw: "10000000000000000000",
      wallet_token_balance: "10",
      wallet_usdc_balance: "4.25",
      wallet_stake_balance_raw: "5000000000000000000",
      wallet_stake_balance: "5",
      wallet_claimable_usdc_raw: "1500000",
      wallet_claimable_usdc: "1.5",
      wallet_claimable_regent_raw: "2000000000000000000",
      wallet_claimable_regent: "2",
      wallet_funded_claimable_regent_raw: "2000000000000000000",
      wallet_funded_claimable_regent: "2"
    }

    @impl true
    def overview(wallet) do
      send(self_or_test(), {:overview, wallet})

      case Process.get(:overview_error) do
        nil ->
          {:ok,
           @public
           |> Map.merge(%{
             wallet_address: wallet,
             paused: Process.get(:paused, false),
             remaining_capacity_raw: Process.get(:capacity_raw, "900000000000000000000"),
             remaining_capacity: "900"
           })
           |> Map.merge(position(wallet))}

        reason ->
          {:error, reason}
      end
    end

    # A public read carries no position at all; a wallet read carries the raw
    # fields the amount and claim proofs consume, overridable per test.
    defp position(nil), do: Map.new(@position, fn {field, _value} -> {field, nil} end)

    defp position(_wallet),
      do:
        Map.merge(@position, %{
          wallet_token_balance_raw: Process.get(:token_raw, "10000000000000000000"),
          wallet_stake_balance_raw: Process.get(:stake_raw, "5000000000000000000"),
          wallet_claimable_usdc_raw: Process.get(:claimable_usdc_raw, "1500000"),
          wallet_claimable_regent_raw: Process.get(:claimable_regent_raw, "2000000000000000000"),
          wallet_funded_claimable_regent_raw:
            Process.get(:funded_regent_raw, "2000000000000000000")
        })

    @impl true
    def confirm(envelope, hash) do
      send(self_or_test(), {:confirm, envelope, hash})

      {:ok,
       %{
         transaction_hash: hash,
         outcome: Process.get(:confirmation_outcome, :confirmed),
         reason: nil
       }}
    end

    @impl true
    def approval_status(_envelope, _hash), do: {:ok, Process.get(:approval_status, :reverted)}

    @impl true
    def approval_current(_envelope) do
      send(self_or_test(), :approval_current)

      case Process.get(:allowance_current, true) do
        true -> :ok
        false -> {:error, :approval_allowance_mismatch}
      end
    end

    defp self_or_test, do: Process.get(:staking_test_pid, self())
  end

  setup do
    previous_client = Application.get_env(:ash_platform, :staking_chain_client)
    previous_clock = Application.get_env(:ash_platform, :wallet_action_clock)
    test_pid = self()

    Application.put_env(:ash_platform, :staking_chain_client, ChainStub)
    Application.put_env(:ash_platform, :wallet_action_clock, fn -> ~U[2026-07-10 12:00:00Z] end)
    Process.put(:staking_test_pid, test_pid)

    on_exit(fn ->
      restore_env(:staking_chain_client, previous_client)
      restore_env(:wallet_action_clock, previous_clock)
    end)

    {:ok, account} =
      Accounts.register_verified("did:privy:staking", @wallet, [@wallet], actor: %System{})

    # Preparation and confirmation are protected writes, so the test carries the
    # same mounted lease a connected socket proves rather than a bare actor.
    %{actor: %Human{human_account_id: account.id}, opts: leased(account.id)}
  end

  test "public overview reads chain truth without a wallet" do
    assert {:ok, %{chain_id: 8453, wallet_address: nil}} = Staking.overview()
    assert_receive {:overview, nil}
  end

  test "account reads are scoped to the verified connected wallet", %{actor: actor} do
    assert {:ok, %{wallet_address: @wallet}} = Staking.account(actor: actor)
    assert_receive {:overview, @wallet}
    assert {:error, _error} = Staking.account()
  end

  # Stake reads the wallet the browser reports, but only after the mounted lease
  # resolves an account that still lists it. Nothing else can name a position.
  test "the staking lookup reads only a wallet the leased account still holds", %{
    actor: actor,
    opts: opts
  } do
    assert {:ok, %{wallet_address: @wallet}} = Staking.account_for_wallet(@wallet, opts)
    assert_receive {:overview, @wallet}

    assert {:error, _unlinked} = Staking.account_for_wallet(@other, opts)
    assert {:error, _malformed} = Staking.account_for_wallet("0xnope", opts)
    assert {:error, _leaseless} = Staking.account_for_wallet(@wallet, actor: actor)
    assert {:error, _anonymous} = Staking.account_for_wallet(@wallet)
    refute_receive {:overview, _wallet}
  end

  # Membership is a session fact, not a chain fact, and it is decided inside the
  # one locked dispatch action rather than in a separate call the page sequences.
  # A wallet the leased account does not hold never reaches a claim.
  test "MEMBERSHIP_IS_LOCAL: the dispatch proves the current wallet inside its own lock", %{
    actor: actor,
    opts: opts
  } do
    {:ok, envelope} = Staking.prepare_claim_usdc(@wallet, opts)

    {:ok, outsider} =
      Accounts.register_verified("did:privy:staking-outsider", @other, [@other], actor: %System{})

    assert {:error, unlinked} =
             Staking.claim_wallet_dispatch(envelope, :action, leased(outsider.id))

    assert refusal(unlinked) == :wrong_signer

    assert {:error, _leaseless} = Staking.claim_wallet_dispatch(envelope, :action, actor: actor)
    assert {:error, _anonymous} = Staking.claim_wallet_dispatch(envelope, :action)

    assert {:ok, %{operation: %{state: :action_dispatched}}} =
             Staking.claim_wallet_dispatch(envelope, :action, opts)
  end

  # A session that no longer resolves an account has said nothing about whose
  # wallet this is, so it is never reported as a wallet the account does not hold.
  test "MEMBERSHIP_IS_LOCAL: a lapsed session is unavailable rather than the wrong wallet", %{
    opts: opts
  } do
    {:ok, envelope} = Staking.prepare_claim_usdc(@wallet, opts)
    SessionAuthority.revoke(%{lineage: opts[:context].session_lease.lineage})

    assert {:error, dispatch} = Staking.claim_wallet_dispatch(envelope, :action, opts)
    assert refusal(dispatch) == :session_unavailable

    assert {:error, preparation} = Staking.prepare_stake(@wallet, "1", opts)
    assert refusal(preparation) == :session_unavailable
  end

  test "stake preparation binds signer, exact approval and ABI calldata", %{opts: opts} do
    assert {:ok, envelope} = Staking.prepare_stake(@wallet, "1.5", opts)

    assert envelope.chain_id == 8453
    assert envelope.to == "0xb027dc261636e30cbc0fe25b2f8e1ed273354ab5"
    assert envelope.value == "0"
    assert envelope.expected_signer == @wallet
    assert envelope.action == "stake"
    assert envelope.idempotency_key == envelope.action_id

    assert envelope.data ==
             "0x7acb7757" <>
               String.pad_leading(
                 Integer.to_string(1_500_000_000_000_000_000, 16) |> String.downcase(),
                 64,
                 "0"
               ) <>
               String.pad_leading(String.trim_leading(@wallet, "0x"), 64, "0")

    assert envelope.approval.amount == "1500000000000000000"
    assert envelope.approval.mode == "exact"
    assert Envelope.valid?(envelope)
  end

  test "the remaining four preparations use only the connected wallet", %{opts: opts} do
    assert {:ok, unstake} = Staking.prepare_unstake(@wallet, "2", opts)
    assert String.starts_with?(unstake.data, "0x8381e182")

    assert {:ok, usdc} = Staking.prepare_claim_usdc(@wallet, opts)
    assert String.starts_with?(usdc.data, "0x42852610")

    assert {:ok, regent} = Staking.prepare_claim_regent(@wallet, opts)
    assert String.starts_with?(regent.data, "0x739c8d0d")

    assert {:ok, restake} = Staking.prepare_claim_and_restake_regent(@wallet, opts)
    assert restake.data == "0xe72a8732"
    assert restake.risk_copy =~ "only when you choose"
  end

  test "wrong signer and invalid amounts fail closed", %{opts: opts} do
    assert {:error, _error} = Staking.prepare_stake(@other, "1", opts)
    assert {:error, _error} = Staking.prepare_stake(@wallet, "0", opts)
    assert {:error, _error} = Staking.prepare_stake(@wallet, "1.0000000000000000001", opts)
  end

  test "earned REGENT cannot be claimed or reinvested while reward inventory is unfunded", %{
    opts: opts
  } do
    Process.put(:funded_regent_raw, "0")

    assert {:error, _error} = Staking.prepare_claim_regent(@wallet, opts)
    assert {:error, _error} = Staking.prepare_claim_and_restake_regent(@wallet, opts)
    Process.delete(:funded_regent_raw)
  end

  # The screen may be stale, so the amount available to claim is proved against
  # current chain truth rather than against what the page last rendered.
  test "a USDC claim of nothing is refused on current chain truth", %{opts: opts} do
    Process.put(:claimable_usdc_raw, "0")
    assert {:error, _error} = Staking.prepare_claim_usdc(@wallet, opts)

    Process.put(:claimable_usdc_raw, "1")
    assert {:ok, %{action: "claim_usdc"}} = Staking.prepare_claim_usdc(@wallet, opts)
    Process.delete(:claimable_usdc_raw)
  end

  # Every limit is read from the one snapshot preparation already takes, so the
  # exact boundary is allowed and one wei past it is refused.
  test "AMOUNT_LIMITS: preparation bounds each amount by the same snapshot", %{opts: opts} do
    Process.put(:token_raw, "10000000000000000000")
    Process.put(:capacity_raw, "900000000000000000000")
    Process.put(:stake_raw, "5000000000000000000")

    for {name, action, amount, expected} <- [
          {"zero", :stake, "0", :refused},
          {"one wei", :stake, "0.000000000000000001", :ok},
          {"exact wallet balance", :stake, "10", :ok},
          {"one wei above the wallet", :stake, "10.000000000000000001", :refused},
          {"exact stake balance", :unstake, "5", :ok},
          {"one wei above the stake", :unstake, "5.000000000000000001", :refused}
        ] do
      result = prepare(action, amount, opts)

      case expected do
        :ok -> assert {:ok, _envelope} = result, "#{name} should prepare"
        :refused -> assert {:error, _refused} = result, "#{name} should be refused"
      end
    end
  end

  test "AMOUNT_LIMITS: a stake may not exceed what the contract can still take", %{opts: opts} do
    Process.put(:token_raw, "5000000000000000000000")
    Process.put(:capacity_raw, "900000000000000000000")

    assert {:ok, _exact} = Staking.prepare_stake(@wallet, "900", opts)

    assert {:error, refused} =
             Staking.prepare_stake(@wallet, "900.000000000000000001", opts)

    assert refusal(refused) == :amount_above_capacity

    Process.put(:capacity_raw, "0")
    assert {:error, _full} = Staking.prepare_stake(@wallet, "1", opts)
  end

  test "AMOUNT_LIMITS: staking is refused while the contract is paused", %{opts: opts} do
    Process.put(:paused, true)

    assert {:error, refused} = Staking.prepare_stake(@wallet, "1", opts)
    assert refusal(refused) == :staking_paused

    # Unstaking and claiming are not gated by the pause.
    assert {:ok, _unstake} = Staking.prepare_unstake(@wallet, "1", opts)
  end

  test "AMOUNT_LIMITS: a compound is refused when the reward exceeds remaining capacity", %{
    opts: opts
  } do
    Process.put(:claimable_regent_raw, "2000000000000000000")
    Process.put(:funded_regent_raw, "2000000000000000000")

    Process.put(:capacity_raw, "2000000000000000000")
    assert {:ok, _exact} = Staking.prepare_claim_and_restake_regent(@wallet, opts)

    Process.put(:capacity_raw, "1999999999999999999")
    assert {:error, refused} = Staking.prepare_claim_and_restake_regent(@wallet, opts)
    assert refusal(refused) == :amount_above_capacity
  end

  # Unavailable facts are their own refusal. A snapshot that could not be read is
  # never a balance of nothing and never a limit of nothing.
  test "AMOUNT_LIMITS: unavailable facts refuse rather than read as zero", %{opts: opts} do
    Process.put(:overview_error, :chain_unavailable)

    for action <- [:stake, :unstake] do
      assert {:error, refused} = prepare(action, "1", opts)
      assert refusal(refused) == :chain_unavailable
    end

    assert {:error, claim} = Staking.prepare_claim_usdc(@wallet, opts)
    assert refusal(claim) == :chain_unavailable
  end

  # The approval's own transaction is complete once its receipt and event agree.
  # The mutable allowance is proved again here, at the dispatch that spends it,
  # and a changed allowance claims nothing at all.
  test "FRESH_APPROVAL: the stake dispatch requires the exact allowance right now", %{opts: opts} do
    {:ok, envelope} = Staking.prepare_stake(@wallet, "1", opts)

    # The approval phase spends nothing, so it never reads the allowance.
    assert {:ok, _approval} = Staking.claim_wallet_dispatch(envelope, :approval, opts)
    refute_receive :approval_current

    {:ok, _released} = Staking.release_unstarted_dispatch(envelope.action_id, :approval, opts)

    Process.put(:allowance_current, false)
    assert {:error, changed} = Staking.claim_wallet_dispatch(envelope, :action, opts)
    assert refusal(changed) == :approval_changed
    assert_receive :approval_current

    Process.put(:allowance_current, true)
    assert {:ok, _claimed} = Staking.claim_wallet_dispatch(envelope, :action, opts)
  end

  test "confirmation accepts an expired submitted envelope but refuses any drift", %{opts: opts} do
    {:ok, envelope} = Staking.prepare_claim_usdc(@wallet, opts)
    hash = "0x" <> String.duplicate("ab", 32)

    # The action phase is claimed before the wallet opens, exactly as the shell
    # does, so confirmation runs against a dispatched operation.
    {:ok, _claimed} = Staking.claim_wallet_dispatch(envelope, :action, opts)

    assert {:ok, %{transaction_hash: ^hash, outcome: :confirmed}} =
             Staking.confirm_wallet_action(envelope, hash, opts)

    assert_receive {:confirm, ^envelope, ^hash}

    refute Envelope.valid?(%{envelope | data: "0xdeadbeef"})
    refute Envelope.valid?(%{envelope | action: "claim_regent"})
    refute Envelope.valid?(%{envelope | to: @other})
    refute Envelope.valid?(%{envelope | expected_signer: @other})
    refute Envelope.valid?(%{envelope | approval: %{mode: "unlimited"}})

    Application.put_env(:ash_platform, :wallet_action_clock, fn -> ~U[2026-07-10 12:11:00Z] end)
    refute Envelope.valid?(envelope)
    assert Envelope.valid_for_confirmation?(envelope)

    assert {:ok, %{transaction_hash: ^hash}} =
             Staking.confirm_wallet_action(envelope, hash, opts)

    assert_receive {:confirm, ^envelope, ^hash}

    assert {:error, _error} =
             Staking.confirm_wallet_action(%{envelope | data: "0xdeadbeef"}, hash, opts)

    refute_receive {:confirm, _, _}
  end

  defp prepare(:stake, amount, opts), do: Staking.prepare_stake(@wallet, amount, opts)
  defp prepare(:unstake, amount, opts), do: Staking.prepare_unstake(@wallet, amount, opts)

  defp refusal(%Ash.Error.Invalid{errors: [%Ash.Error.Invalid.Unavailable{reason: reason} | _]}),
    do: reason

  defp refusal(_other), do: nil

  defp restore_env(key, nil), do: Application.delete_env(:ash_platform, key)
  defp restore_env(key, value), do: Application.put_env(:ash_platform, key, value)
end
