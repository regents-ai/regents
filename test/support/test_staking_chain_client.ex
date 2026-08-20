defmodule AshPlatform.TestStakingChainClient do
  @behaviour AshPlatform.Staking.ChainClient

  @wallet "0x1111111111111111111111111111111111111111"
  @balances %{
    token: "10000000000000000000",
    stake: "5000000000000000000",
    usdc_wallet: "4250000",
    usdc_claimable: "1500000",
    regent_claimable: "2000000000000000000",
    regent_funded: "2000000000000000000"
  }

  @doc "The wallet this fake accepts as the signer, so a test can drive a switch."
  def signer, do: Application.get_env(:ash_platform, :test_staking_signer, @wallet)

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
       wallet_token_balance_raw: raw(wallet, :token),
       wallet_token_balance: regent(wallet, :token),
       wallet_usdc_balance_raw: raw(wallet, :usdc_wallet),
       wallet_usdc_balance: usdc(wallet, :usdc_wallet),
       wallet_stake_balance_raw: raw(wallet, :stake),
       wallet_stake_balance: regent(wallet, :stake),
       wallet_claimable_usdc_raw: raw(wallet, :usdc_claimable),
       wallet_claimable_usdc: usdc(wallet, :usdc_claimable),
       wallet_claimable_regent_raw: raw(wallet, :regent_claimable),
       wallet_claimable_regent: regent(wallet, :regent_claimable),
       wallet_funded_claimable_regent_raw: raw(wallet, :regent_funded),
       wallet_funded_claimable_regent: regent(wallet, :regent_funded)
     }}
  end

  @impl true
  def confirm(envelope, "0x" <> hash = transaction_hash, _approval_hash)
      when byte_size(hash) == 64 do
    with :ok <- Application.get_env(:ash_platform, :test_staking_confirmation_result, :ok),
         true <- envelope.expected_signer == signer() do
      confirmed(envelope.expected_signer, transaction_hash)
    else
      :reverted -> {:error, :transaction_reverted}
      _ -> {:error, :transaction_mismatch}
    end
  end

  def confirm(_envelope, _transaction_hash, _approval_hash),
    do: {:error, :invalid_confirmation}

  # The authoritative reread is a fact of its own, so the fake can withhold it
  # exactly the way an unavailable Base read does.
  defp confirmed(wallet, transaction_hash) do
    if Application.get_env(:ash_platform, :test_staking_refresh_error, false) do
      {:ok,
       %{
         transaction_hash: transaction_hash,
         receipt_verified: true,
         reread_verified: false,
         staking: nil,
         reason: :chain_unavailable
       }}
    else
      {:ok, staking} = overview(wallet)

      {:ok,
       %{
         transaction_hash: transaction_hash,
         receipt_verified: true,
         reread_verified: true,
         staking: staking,
         reason: nil
       }}
    end
  end

  # A successful approval receipt is only success once the allowance reread agrees.
  @impl true
  def approval_status(_envelope, _transaction_hash) do
    case Application.get_env(:ash_platform, :test_staking_approval_status, :success) do
      :success ->
        if Application.get_env(:ash_platform, :test_staking_allowance_verified, true),
          do: {:ok, :success},
          else: {:ok, :pending}

      status ->
        {:ok, status}
    end
  end

  defp raw(nil, _key), do: nil

  defp raw(_wallet, key),
    do:
      :ash_platform
      |> Application.get_env(:test_staking_balances, %{})
      |> Map.get(key, Map.fetch!(@balances, key))

  defp regent(wallet, key), do: scaled(raw(wallet, key), 18)
  defp usdc(wallet, key), do: scaled(raw(wallet, key), 6)

  defp scaled(nil, _decimals), do: nil

  defp scaled(raw, decimals) do
    raw
    |> Decimal.new()
    |> Decimal.div(Decimal.new(Integer.pow(10, decimals)))
    |> Decimal.normalize()
    |> Decimal.to_string(:normal)
  end
end
