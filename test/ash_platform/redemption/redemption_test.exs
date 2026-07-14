defmodule AshPlatform.RedemptionTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.{Accounts, Redemption}
  alias AshPlatform.Actors.{Human, System}
  alias AshPlatform.WalletActions.Envelope

  @wallet "0x1111111111111111111111111111111111111111"
  @other "0x2222222222222222222222222222222222222222"
  @animata_i "0x78402119ec6349a0d41f12b54938de7bf783c923"
  @animata_ii "0x903c4c1e8b8532fbd3575482d942d493eb9266e2"

  defmodule ChainStub do
    @behaviour AshPlatform.Redemption.ChainClient

    @impl true
    def overview(wallet, collection, token_id) do
      send(Process.get(:redemption_test_pid, self()), {:overview, wallet, collection, token_id})

      {:ok,
       %{
         chain_id: 8453,
         chain_label: "Base",
         redeemer_address: "0x71065b775a590c43933f10c0055dc7d74afabb0e",
         animata_i_address: "0x78402119ec6349a0d41f12b54938de7bf783c923",
         animata_ii_address: "0x903c4c1e8b8532fbd3575482d942d493eb9266e2",
         result_collection_address: "0x2208aadbdecd47d3b4430b5b75a175f6d885d487",
         usdc_address: "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913",
         price_raw: "80000000",
         price: "80",
         payout_raw: "5000000000000000000000000",
         payout: "5000000",
         vest_duration_seconds: 604_800,
         wallet_address: wallet,
         selected_collection: collection,
         token_id: token_id,
         nft_owner: if(wallet && token_id, do: Process.get(:nft_owner, wallet), else: nil),
         nft_approved: if(wallet, do: Process.get(:nft_approved, true), else: nil),
         usdc_balance_raw: if(wallet, do: Process.get(:usdc_balance_raw, "100000000"), else: nil),
         usdc_balance: if(wallet, do: "100", else: nil),
         usdc_allowance_raw:
           if(wallet, do: Process.get(:usdc_allowance_raw, "80000000"), else: nil),
         usdc_allowance: if(wallet, do: "80", else: nil),
         claimable_raw:
           if(wallet, do: Process.get(:claimable_raw, "1000000000000000000"), else: nil),
         claimable: if(wallet, do: "1", else: nil),
         vest_pool_raw: if(wallet, do: "5000000000000000000000000", else: nil),
         vest_pool: if(wallet, do: "5000000", else: nil),
         vest_released_raw: if(wallet, do: "1000000000000000000", else: nil),
         vest_released: if(wallet, do: "1", else: nil),
         vest_claimed_raw: if(wallet, do: "0", else: nil),
         vest_claimed: if(wallet, do: "0", else: nil),
         vest_start: if(wallet, do: 1_700_000_000, else: nil),
         result_token_id: if(token_id, do: 1123, else: nil)
       }}
    end

    @impl true
    def confirm(envelope, transaction_hash) do
      send(Process.get(:redemption_test_pid, self()), {:confirm, envelope, transaction_hash})

      case Process.get(:redemption_confirmation, :ok) do
        :reverted ->
          {:error, :transaction_reverted}

        :ok ->
          {:ok, refreshed} =
            overview(
              envelope.expected_signer,
              envelope.arguments[:collection],
              envelope.arguments[:token_id]
            )

          {:ok,
           %{
             transaction_hash: transaction_hash,
             receipt_verified: true,
             redemption: refreshed,
             refresh_error: nil
           }}
      end
    end
  end

  setup do
    previous_client = Application.get_env(:ash_platform, :redemption_chain_client)
    previous_clock = Application.get_env(:ash_platform, :wallet_action_clock)
    Application.put_env(:ash_platform, :redemption_chain_client, ChainStub)
    Application.put_env(:ash_platform, :wallet_action_clock, fn -> ~U[2026-07-10 12:00:00Z] end)
    Process.put(:redemption_test_pid, self())

    on_exit(fn ->
      restore(:redemption_chain_client, previous_client)
      restore(:wallet_action_clock, previous_clock)
    end)

    {:ok, account} =
      Accounts.register_verified("did:privy:redemption", @wallet, [@wallet], actor: %System{})

    %{actor: %Human{human_account_id: account.id}}
  end

  test "public facts and wallet account state come from Base", %{actor: actor} do
    assert {:ok, %{price_raw: "80000000", wallet_address: nil}} = Redemption.overview()
    assert_receive {:overview, nil, nil, nil}

    assert {:ok, %{wallet_address: @wallet, token_id: 42, nft_owner: @wallet}} =
             Redemption.account("animata_i", 42, actor: actor)

    assert_receive {:overview, @wallet, @animata_i, 42}
    assert {:error, _} = Redemption.account("animata_i", 42)
  end

  test "the four actions are separate signed exact-zero-value envelopes", %{actor: actor} do
    assert {:ok, nft} = Redemption.prepare_nft_approval(@wallet, "animata_i", actor: actor)
    assert nft.action == "approve_nft_collection"
    assert nft.to == @animata_i

    assert nft.arguments == %{
             approved: true,
             collection: @animata_i,
             operator: "0x71065b775a590c43933f10c0055dc7d74afabb0e"
           }

    assert Envelope.valid?(nft, resource: "animata_redemption", to: @animata_i)

    assert {:ok, usdc} = Redemption.prepare_usdc_approval(@wallet, actor: actor)
    assert usdc.action == "approve_exact_usdc"
    assert usdc.arguments.amount_atomic == "80000000"
    assert usdc.arguments.mode == "exact"

    assert {:ok, redeem} = Redemption.prepare_redeem(@wallet, "animata_ii", 42, actor: actor)
    assert redeem.action == "redeem"
    assert redeem.arguments.collection == @animata_ii
    assert redeem.arguments.token_id == 42

    assert {:ok, claim} = Redemption.prepare_claim(@wallet, actor: actor)
    assert claim.action == "claim"

    for envelope <- [nft, usdc, redeem, claim] do
      assert envelope.chain_id == 8453
      assert envelope.value == "0"
      assert envelope.expected_signer == @wallet
      assert envelope.idempotency_key == envelope.action_id
      assert is_binary(envelope.confirmation_token)
    end
  end

  test "wrong signer, collection, token id and result collection fail closed", %{actor: actor} do
    assert {:error, _} = Redemption.prepare_claim(@other, actor: actor)
    assert {:error, _} = Redemption.prepare_redeem(@wallet, "result_collection", 1, actor: actor)
    assert {:error, _} = Redemption.prepare_redeem(@wallet, "animata_i", 0, actor: actor)
    assert {:error, _} = Redemption.prepare_redeem(@wallet, "animata_i", 1000, actor: actor)
  end

  test "redeem preparation requires ownership, NFT approval, sufficient balance and exact allowance",
       %{
         actor: actor
       } do
    Process.put(:nft_owner, @other)
    assert {:error, _} = Redemption.prepare_redeem(@wallet, "animata_i", 42, actor: actor)

    Process.put(:nft_owner, @wallet)
    Process.put(:nft_approved, false)
    assert {:error, _} = Redemption.prepare_redeem(@wallet, "animata_i", 42, actor: actor)

    Process.put(:nft_approved, true)
    Process.put(:usdc_balance_raw, "79999999")
    assert {:error, _} = Redemption.prepare_redeem(@wallet, "animata_i", 42, actor: actor)

    Process.put(:usdc_balance_raw, "100000000")

    for allowance <- ["79999999", "80000001", "160000000"] do
      Process.put(:usdc_allowance_raw, allowance)
      assert {:error, _} = Redemption.prepare_redeem(@wallet, "animata_i", 42, actor: actor)
    end

    Process.put(:usdc_allowance_raw, "80000000")

    assert {:ok, %{action: "redeem"}} =
             Redemption.prepare_redeem(@wallet, "animata_i", 42, actor: actor)
  end

  test "claim preparation requires a positive unlocked amount", %{actor: actor} do
    Process.put(:claimable_raw, "0")
    assert {:error, _} = Redemption.prepare_claim(@wallet, actor: actor)

    Process.put(:claimable_raw, "1")
    assert {:ok, %{action: "claim"}} = Redemption.prepare_claim(@wallet, actor: actor)
  end

  test "confirmation accepts an expired submitted action but rejects signed-field drift", %{
    actor: actor
  } do
    assert {:ok, envelope} = Redemption.prepare_claim(@wallet, actor: actor)
    hash = "0x" <> String.duplicate("ab", 32)

    assert {:ok, %{transaction_hash: ^hash, receipt_verified: true}} =
             Redemption.confirm_wallet_action(envelope, hash, actor: actor)

    assert_receive {:confirm, ^envelope, ^hash}

    Application.put_env(:ash_platform, :wallet_action_clock, fn -> ~U[2026-07-10 12:11:00Z] end)
    refute Envelope.valid?(envelope, resource: "animata_redemption", to: envelope.to)

    assert Envelope.valid_for_confirmation?(envelope,
             resource: "animata_redemption",
             to: envelope.to
           )

    assert {:error, _} =
             Redemption.confirm_wallet_action(%{envelope | data: "0xdeadbeef"}, hash,
               actor: actor
             )

    refute_receive {:confirm, _, _}
  end

  defp restore(key, nil), do: Application.delete_env(:ash_platform, key)
  defp restore(key, value), do: Application.put_env(:ash_platform, key, value)
end
