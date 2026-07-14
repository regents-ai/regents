defmodule AshPlatform.TestStakingChainClient do
  @behaviour AshPlatform.Staking.ChainClient

  @wallet "0x1111111111111111111111111111111111111111"

  @impl true
  def overview(wallet) do
    {:ok,
     %{
       chain_id: 8453,
       chain_label: "Base",
       contract_address: "0xb027dc261636e30cbc0fe25b2f8e1ed273354ab5",
       stake_token_address: "0x6f89bca4ea5931edfcb09786267b251dee752b07",
       usdc_address: "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913",
       paused: false,
       total_staked_raw: "100000000000000000000",
       total_staked: "100",
       wallet_address: wallet,
       wallet_token_balance_raw: if(wallet, do: "10000000000000000000", else: nil),
       wallet_token_balance: if(wallet, do: "10", else: nil),
       wallet_usdc_balance_raw: if(wallet, do: "4250000", else: nil),
       wallet_usdc_balance: if(wallet, do: "4.25", else: nil),
       wallet_stake_balance_raw: if(wallet, do: "5000000000000000000", else: nil),
       wallet_stake_balance: if(wallet, do: "5", else: nil),
       wallet_claimable_usdc_raw: if(wallet, do: "1500000", else: nil),
       wallet_claimable_usdc: if(wallet, do: "1.5", else: nil),
       wallet_claimable_regent_raw: if(wallet, do: "2000000000000000000", else: nil),
       wallet_claimable_regent: if(wallet, do: "2", else: nil),
       wallet_funded_claimable_regent_raw: if(wallet, do: "2000000000000000000", else: nil),
       wallet_funded_claimable_regent: if(wallet, do: "2", else: nil)
     }}
  end

  @impl true
  def confirm(envelope, "0x" <> hash = transaction_hash, _approval_hash)
      when byte_size(hash) == 64 do
    with :ok <- Application.get_env(:ash_platform, :test_staking_confirmation_result, :ok),
         true <- envelope.expected_signer == @wallet,
         {:ok, staking} <- overview(@wallet) do
      {:ok,
       %{
         transaction_hash: transaction_hash,
         receipt_verified: true,
         staking: staking,
         refresh_error: nil
       }}
    else
      :reverted -> {:error, :transaction_reverted}
      _ -> {:error, :transaction_mismatch}
    end
  end

  def confirm(_envelope, _transaction_hash, _approval_hash),
    do: {:error, :invalid_confirmation}

  @impl true
  def approval_status(_envelope, _transaction_hash),
    do: {:ok, Application.get_env(:ash_platform, :test_staking_approval_status, :success)}
end
