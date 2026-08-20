defmodule AshPlatform.StakingTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.{Accounts, Staking}
  alias AshPlatform.Actors.{Human, System}
  alias AshPlatform.WalletActions.Envelope

  @wallet "0x1111111111111111111111111111111111111111"
  @other "0x2222222222222222222222222222222222222222"

  defmodule ChainStub do
    @behaviour AshPlatform.Staking.ChainClient

    @public %{
      chain_id: 8453,
      chain_label: "Base",
      contract_address: "0xb027dc261636e30cbc0fe25b2f8e1ed273354ab5",
      paused: false,
      total_staked: "100",
      total_staked_raw: "100000000000000000000"
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

      {:ok, @public |> Map.put(:wallet_address, wallet) |> Map.merge(position(wallet))}
    end

    # A public read carries no position at all; a wallet read carries the raw
    # fields the amount and claim proofs consume, overridable per test.
    defp position(nil), do: Map.new(@position, fn {field, _value} -> {field, nil} end)

    defp position(_wallet),
      do:
        Map.merge(@position, %{
          wallet_claimable_usdc_raw: Process.get(:claimable_usdc_raw, "1500000"),
          wallet_funded_claimable_regent_raw:
            Process.get(:funded_regent_raw, "2000000000000000000")
        })

    @impl true
    def confirm(envelope, hash, approval_hash) do
      send(self_or_test(), {:confirm, envelope, hash, approval_hash})

      overview(envelope.expected_signer)
      |> then(fn {:ok, staking} ->
        {:ok,
         %{
           transaction_hash: hash,
           receipt_verified: true,
           reread_verified: true,
           staking: staking,
           reason: nil
         }}
      end)
    end

    @impl true
    def approval_status(_envelope, _hash), do: {:ok, Process.get(:approval_status, :reverted)}

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

  test "confirmation accepts an expired submitted envelope but refuses any drift", %{opts: opts} do
    {:ok, envelope} = Staking.prepare_claim_usdc(@wallet, opts)
    hash = "0x" <> String.duplicate("ab", 32)

    # The action phase is claimed before the wallet opens, exactly as the shell
    # does, so confirmation runs against a dispatched operation.
    {:ok, _claimed} = Staking.claim_wallet_dispatch(envelope.action_id, :action, opts)

    assert {:ok, %{transaction_hash: ^hash, staking: %{wallet_address: @wallet}}} =
             Staking.confirm_wallet_action(envelope, hash, nil, opts)

    assert_receive {:confirm, ^envelope, ^hash, nil}

    refute Envelope.valid?(%{envelope | data: "0xdeadbeef"})
    refute Envelope.valid?(%{envelope | action: "claim_regent"})
    refute Envelope.valid?(%{envelope | to: @other})
    refute Envelope.valid?(%{envelope | expected_signer: @other})
    refute Envelope.valid?(%{envelope | approval: %{mode: "unlimited"}})

    Application.put_env(:ash_platform, :wallet_action_clock, fn -> ~U[2026-07-10 12:11:00Z] end)
    refute Envelope.valid?(envelope)
    assert Envelope.valid_for_confirmation?(envelope)

    assert {:ok, %{transaction_hash: ^hash}} =
             Staking.confirm_wallet_action(envelope, hash, nil, opts)

    assert_receive {:confirm, ^envelope, ^hash, nil}

    assert {:error, _error} =
             Staking.confirm_wallet_action(%{envelope | data: "0xdeadbeef"}, hash, nil, opts)

    refute_receive {:confirm, _, _, _}
  end

  defp restore_env(key, nil), do: Application.delete_env(:ash_platform, key)
  defp restore_env(key, value), do: Application.put_env(:ash_platform, key, value)
end
