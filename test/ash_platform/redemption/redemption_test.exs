defmodule AshPlatform.RedemptionTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.Redemption

  @wallet "0x1111111111111111111111111111111111111111"
  @other "0x2222222222222222222222222222222222222222"
  @animata_i "0x78402119ec6349a0d41f12b54938de7bf783c923"

  defmodule ChainStub do
    @behaviour AshPlatform.Redemption.ChainClient

    @impl true
    def overview(wallet, collection, token_id) do
      send(Process.get(:redemption_test_pid, self()), {:overview, wallet, collection, token_id})

      {:ok,
       %{
         chain_id: 8453,
         chain_label: "Base",
         block_number: 42,
         block_hash: "0x" <> String.duplicate("2c", 32),
         redeemer_address: "0x71065b775a590c43933f10c0055dc7d74afabb0e",
         animata_i_address: "0x78402119ec6349a0d41f12b54938de7bf783c923",
         animata_ii_address: "0x903c4c1e8b8532fbd3575482d942d493eb9266e2",
         result_collection_address: "0x2208aadbdecd47d3b4430b5b75a175f6d885d487",
         usdc_address: "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913",
         regent_address: "0x6f89bca4ea5931edfcb09786267b251dee752b07",
         price_raw: "80000000",
         price: "80",
         payout_raw: "5000000000000000000000000",
         payout: "5000000",
         vest_duration_seconds: 604_800,
         max_source_token_id: 999,
         animata_i_held_by_redeemer: 327,
         animata_ii_held_by_redeemer: 284,
         regents_club_ready: 388,
         wallet_address: wallet,
         selected_collection: collection,
         token_id: token_id,
         nft_owner: owner(wallet, token_id),
         nft_owner_unavailable: token_id != nil and Process.get(:owner_unavailable, false),
         nft_approved: if(wallet, do: Process.get(:nft_approved, true), else: nil),
         usdc_balance_raw: if(wallet, do: Process.get(:usdc_balance_raw, "100000000")),
         usdc_balance: if(wallet, do: "100"),
         usdc_allowance_raw: if(wallet, do: Process.get(:usdc_allowance_raw, "80000000")),
         usdc_allowance: if(wallet, do: "80"),
         claimable_raw: if(wallet, do: Process.get(:claimable_raw, "1000000000000000000")),
         claimable: if(wallet, do: "1"),
         vest_pool_raw: if(wallet, do: "5000000000000000000000000"),
         vest_pool: if(wallet, do: "5000000"),
         vest_released_raw: if(wallet, do: "1000000000000000000"),
         vest_released: if(wallet, do: "1"),
         vest_claimed_raw: if(wallet, do: "0"),
         vest_claimed: if(wallet, do: "0"),
         vest_start: if(wallet, do: 1_700_000_000),
         result_token_id: if(token_id, do: 1123)
       }}
    end

    defp owner(nil, _), do: nil
    defp owner(_, nil), do: nil

    defp owner(wallet, _token_id) do
      if Process.get(:owner_unavailable, false),
        do: nil,
        else: Process.get(:nft_owner, wallet)
    end
  end

  setup do
    previous_client = Application.get_env(:ash_platform, :redemption_chain_client)
    Application.put_env(:ash_platform, :redemption_chain_client, ChainStub)
    Process.put(:redemption_test_pid, self())
    on_exit(fn -> restore(:redemption_chain_client, previous_client) end)

    :ok
  end

  test "CHAIN_FACTS_ONLY: account reads accept the active connected wallet without a login" do
    assert {:ok, %{wallet_address: nil}} = Redemption.overview()
    assert_receive {:overview, nil, nil, nil}

    assert {:ok, %{wallet_address: @wallet, token_id: 42}} =
             Redemption.account_for_wallet(@wallet, "animata_i", 42)

    assert_receive {:overview, @wallet, @animata_i, 42}

    assert {:ok, %{wallet_address: @other}} =
             Redemption.account_for_wallet(@other, "animata_i", 42)

    assert {:error, _} = Redemption.account_for_wallet("not-a-wallet", "animata_i", 42)
  end

  test "NEXT_ONCHAIN_STEP: selection exposes exactly the action Base currently requires" do
    base = facts()
    assert Redemption.next_step(%{base | token_id: nil}, @wallet) == :token_selection_required
    assert Redemption.next_step(%{base | nft_approved: false}, @wallet) == :nft_approval_required

    assert Redemption.next_step(%{base | usdc_allowance_raw: "0"}, @wallet) ==
             :exact_usdc_approval_required

    assert Redemption.next_step(%{base | usdc_balance_raw: "1"}, @wallet) == :insufficient_usdc
    assert Redemption.next_step(base, @wallet) == :ready
  end

  test "APPROVE_NFT: preparation rereads ownership and the current step" do
    Process.put(:nft_approved, false)
    assert {:ok, envelope} = Redemption.prepare_nft_approval(@wallet, "animata_i", 42)
    assert envelope.action == "approve_nft_collection"
    assert envelope.to == @animata_i
    assert_receive {:overview, @wallet, @animata_i, 42}

    Process.put(:nft_approved, true)
    assert {:error, error} = Redemption.prepare_nft_approval(@wallet, "animata_i", 42)
    assert refusal(error) == :ready
  end

  test "APPROVE_80_USDC: exact approval is available only at its current step" do
    Process.put(:usdc_allowance_raw, "0")
    assert {:ok, envelope} = Redemption.prepare_usdc_approval(@wallet, "animata_i", 42)
    assert envelope.action == "approve_exact_usdc"
    assert envelope.arguments.amount_atomic == "80000000"
    assert envelope.arguments.mode == "exact"

    Process.put(:nft_approved, false)
    assert {:error, error} = Redemption.prepare_usdc_approval(@wallet, "animata_i", 42)
    assert refusal(error) == :nft_approval_required
  end

  test "REDEEM_NOW: identical eligible clicks remain distinct direct requests" do
    assert {:ok, first} = Redemption.prepare_redeem(@wallet, "animata_i", 42)
    assert {:ok, second} = Redemption.prepare_redeem(@wallet, "animata_i", 42)
    assert first.action == "redeem"
    refute first.action_id == second.action_id
  end

  test "CLAIM_UNLOCKED: claim rereads positive chain state" do
    assert {:ok, %{action: "claim"}} = Redemption.prepare_claim(@wallet)
    Process.put(:claimable_raw, "0")
    assert {:error, error} = Redemption.prepare_claim(@wallet)
    assert refusal(error) == :nothing_claimable
  end

  test "CHAIN_AUTHORITY: owner failure and changed approvals refuse before an envelope" do
    Process.put(:owner_unavailable, true)
    assert {:error, error} = Redemption.prepare_redeem(@wallet, "animata_i", 42)
    assert refusal(error) == :nft_owner_unavailable

    Process.put(:owner_unavailable, false)
    Process.put(:usdc_allowance_raw, "0")
    assert {:error, error} = Redemption.prepare_redeem(@wallet, "animata_i", 42)
    assert refusal(error) == :exact_usdc_approval_required
  end

  defp facts do
    %{
      token_id: 42,
      nft_owner: @wallet,
      nft_owner_unavailable: false,
      nft_approved: true,
      usdc_balance_raw: "100000000",
      usdc_allowance_raw: "80000000"
    }
  end

  defp refusal(%Ash.Error.Invalid{errors: [%Ash.Error.Invalid.Unavailable{reason: reason} | _]}),
    do: reason

  defp refusal(_), do: nil
  defp restore(key, nil), do: Application.delete_env(:ash_platform, key)
  defp restore(key, value), do: Application.put_env(:ash_platform, key, value)
end
