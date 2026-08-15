defmodule AshPlatform.TestRedemptionChainClient do
  @behaviour AshPlatform.Redemption.ChainClient

  @wallet "0x1111111111111111111111111111111111111111"

  @impl true
  def overview(wallet, collection, token_id) do
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
       nft_owner: if(wallet && token_id, do: wallet, else: nil),
       nft_approved: if(wallet, do: nft_approved?(), else: nil),
       usdc_balance_raw: if(wallet, do: "100000000", else: nil),
       usdc_balance: if(wallet, do: "100", else: nil),
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
       vest_start: if(wallet, do: 1_700_000_000, else: nil),
       result_token_id:
         if(token_id && Application.get_env(:ash_platform, :test_redemption_result_ready, false),
           do: 1123,
           else: nil
         )
     }}
  end

  @impl true
  def confirm(envelope, "0x" <> hash = transaction_hash) when byte_size(hash) == 64 do
    with :ok <- Application.get_env(:ash_platform, :test_redemption_confirmation_result, :ok),
         true <- envelope.expected_signer == @wallet,
         :ok <- record_action_state(envelope.action) do
      if Application.get_env(:ash_platform, :test_redemption_refresh_error, false) do
        {:ok,
         %{
           transaction_hash: transaction_hash,
           receipt_verified: true,
           reread_verified: false,
           redemption: nil,
           reason: :chain_unavailable
         }}
      else
        {:ok, redemption} =
          overview(@wallet, envelope.arguments[:collection], envelope.arguments[:token_id])

        {:ok,
         %{
           transaction_hash: transaction_hash,
           receipt_verified: true,
           reread_verified: true,
           redemption: redemption,
           reason: nil
         }}
      end
    else
      :reverted -> {:error, :transaction_reverted}
      _ -> {:error, :transaction_mismatch}
    end
  end

  def confirm(_envelope, _transaction_hash), do: {:error, :invalid_confirmation}

  defp record_action_state("approve_nft_collection") do
    Application.put_env(:ash_platform, :test_redemption_nft_approved, true)
  end

  defp record_action_state("approve_exact_usdc") do
    Application.put_env(:ash_platform, :test_redemption_usdc_allowance, 80_000_000)
  end

  defp record_action_state("redeem") do
    Application.put_env(:ash_platform, :test_redemption_result_ready, true)
  end

  defp record_action_state("claim"), do: :ok

  defp nft_approved? do
    Application.get_env(:ash_platform, :test_redemption_nft_approved, not browser_test?())
  end

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
