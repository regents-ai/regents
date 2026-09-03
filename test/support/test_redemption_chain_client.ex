defmodule AshPlatform.TestRedemptionChainClient do
  @behaviour AshPlatform.Redemption.ChainClient

  @impl true
  def overview(wallet, collection, token_id) do
    {:ok,
     %{
       chain_id: 8453,
       chain_label: "Base",
       block_number: 1_234,
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
       animata_i_supply: 327,
       animata_ii_supply: 284,
       regents_club_supply: 1998,
       regents_club_claimed: 1610,
       wallet_address: wallet,
       selected_collection: collection,
       token_id: token_id,
       nft_owner: nft_owner(wallet, token_id),
       nft_owner_unavailable: token_id != nil and owner_unavailable?(),
       nft_approved: if(wallet, do: nft_approved?(), else: nil),
       usdc_balance_raw: if(wallet, do: Integer.to_string(usdc_balance()), else: nil),
       usdc_balance: if(wallet, do: format_units(usdc_balance(), 6), else: nil),
       usdc_allowance_raw: if(wallet, do: Integer.to_string(usdc_allowance()), else: nil),
       usdc_allowance: if(wallet, do: format_units(usdc_allowance(), 6), else: nil),
       claimable_raw: if(wallet, do: "1000000000000000000", else: nil),
       claimable: if(wallet, do: "1", else: nil),
       vest_pool_raw: if(wallet, do: "5000000000000000000000000", else: nil),
       vest_pool: if(wallet, do: "5000000", else: nil),
       vest_released_raw: if(wallet, do: "1000000000000000000", else: nil),
       vest_released: if(wallet, do: "1", else: nil),
       vest_claimed_raw: if(wallet, do: "0", else: nil),
       vest_claimed: if(wallet, do: "0", else: nil),
       vest_start: if(wallet, do: 1_700_000_000, else: nil)
     }}
  end

  # An owner that could not be read is its own state: never a nil owner, and
  # never someone else's address.
  defp nft_owner(wallet, token_id) do
    if wallet && token_id && not owner_unavailable?() do
      Application.get_env(:ash_platform, :test_redemption_nft_owner, wallet)
    end
  end

  defp owner_unavailable?,
    do: Application.get_env(:ash_platform, :test_redemption_owner_unavailable, false)

  defp nft_approved?,
    do: Application.get_env(:ash_platform, :test_redemption_nft_approved, not browser_test?())

  defp usdc_balance,
    do: Application.get_env(:ash_platform, :test_redemption_usdc_balance, 100_000_000)

  defp usdc_allowance do
    Application.get_env(
      :ash_platform,
      :test_redemption_usdc_allowance,
      if(browser_test?(), do: 0, else: 80_000_000)
    )
  end

  defp browser_test?, do: System.get_env("ASH_PLATFORM_BROWSER_TEST") == "1"

  defp format_units(value, decimals) do
    value
    |> Decimal.new()
    |> Decimal.div(Decimal.new(Integer.pow(10, decimals)))
    |> Decimal.normalize()
    |> Decimal.to_string(:normal)
  end
end
