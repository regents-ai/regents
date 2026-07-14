defmodule AshPlatform.Staking.RpcClient do
  @moduledoc false
  @behaviour AshPlatform.Staking.ChainClient

  alias AshPlatform.WalletActions.{Abi, Envelope, Rpc}

  @overview_timeout 12_000
  @chain_id 8453

  @impl true
  def overview(wallet_address) do
    task = Task.async(fn -> do_overview(wallet_address) end)

    case Task.yield(task, @overview_timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      _ -> {:error, :chain_timeout}
    end
  end

  defp do_overview(wallet_address) do
    with :ok <- Rpc.verify_base_chain(),
         {:ok, paused} <- Rpc.call_bool(Abi.staking_address(), Abi.encode_read("paused")),
         {:ok, total_staked} <-
           Rpc.call_uint(Abi.staking_address(), Abi.encode_read("total_staked")),
         {:ok, stake_token} <-
           Rpc.call_address(Abi.staking_address(), Abi.encode_read("stake_token")),
         {:ok, usdc} <- Rpc.call_address(Abi.staking_address(), Abi.encode_read("usdc")),
         true <- stake_token == Abi.normalize_address!(Abi.stake_token_address()),
         true <- usdc == Abi.normalize_address!(Abi.usdc_address()),
         {:ok, account} <- account_reads(wallet_address, stake_token, usdc) do
      {:ok,
       Map.merge(account, %{
         chain_id: @chain_id,
         chain_label: "Base",
         contract_address: Abi.normalize_address!(Abi.staking_address()),
         stake_token_address: stake_token,
         usdc_address: usdc,
         paused: paused,
         total_staked_raw: Integer.to_string(total_staked),
         total_staked: Rpc.format_units(total_staked, 18)
       })}
    else
      false -> {:error, :contract_constants_mismatch}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def confirm(envelope, tx_hash, approval_transaction_hash) do
    with true <- Envelope.valid_for_confirmation?(envelope),
         true <- Rpc.valid_hash?(tx_hash),
         :ok <- Rpc.verify_base_chain(),
         :ok <- verify_approval(envelope, approval_transaction_hash),
         :ok <-
           Rpc.confirmed_transaction(
             tx_hash,
             envelope.expected_signer,
             envelope.to,
             envelope.data
           ),
         result <- confirmation_result(envelope, tx_hash) do
      result
    else
      false -> {:error, :invalid_confirmation}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def approval_status(%{approval: approval, expected_signer: signer} = envelope, hash)
      when is_map(approval) do
    with true <- Envelope.valid_for_confirmation?(envelope),
         true <- Rpc.valid_hash?(hash),
         :ok <- Rpc.verify_base_chain(),
         result <-
           Rpc.submission_status(
             hash,
             signer,
             approval_field(approval, :token),
             approval_field(approval, :data)
           ) do
      result
    else
      false -> {:error, :invalid_approval_confirmation}
      {:error, reason} -> {:error, reason}
    end
  end

  def approval_status(_envelope, _hash), do: {:error, :invalid_approval_confirmation}

  defp confirmation_result(envelope, tx_hash) do
    case overview(envelope.expected_signer) do
      {:ok, refreshed} ->
        {:ok,
         %{
           transaction_hash: String.downcase(tx_hash),
           receipt_verified: true,
           staking: refreshed,
           refresh_error: nil
         }}

      {:error, reason} ->
        {:ok,
         %{
           transaction_hash: String.downcase(tx_hash),
           receipt_verified: true,
           staking: nil,
           refresh_error: reason
         }}
    end
  end

  defp verify_approval(%{approval: nil}, nil), do: :ok
  defp verify_approval(%{approval: nil}, _hash), do: {:error, :unexpected_approval}
  defp verify_approval(%{approval: _approval}, nil), do: {:error, :approval_required}

  defp verify_approval(%{approval: approval, expected_signer: signer}, hash) do
    with true <- Rpc.valid_hash?(hash),
         token <- normalize_or_nil(approval_field(approval, :token)),
         data <- String.downcase(approval_field(approval, :data) || ""),
         :ok <- Rpc.confirmed_transaction(hash, signer, token, data) do
      :ok
    else
      false -> {:error, :invalid_approval_confirmation}
      nil -> {:error, :invalid_approval_confirmation}
      {:error, reason} -> {:error, reason}
    end
  end

  defp account_reads(nil, _stake_token, _usdc) do
    {:ok,
     %{
       wallet_address: nil,
       wallet_token_balance_raw: nil,
       wallet_token_balance: nil,
       wallet_usdc_balance_raw: nil,
       wallet_usdc_balance: nil,
       wallet_stake_balance_raw: nil,
       wallet_stake_balance: nil,
       wallet_claimable_usdc_raw: nil,
       wallet_claimable_usdc: nil,
       wallet_claimable_regent_raw: nil,
       wallet_claimable_regent: nil,
       wallet_funded_claimable_regent_raw: nil,
       wallet_funded_claimable_regent: nil
     }}
  end

  defp account_reads(wallet_address, stake_token, usdc) do
    wallet = Abi.normalize_address!(wallet_address)

    with {:ok, token_balance} <-
           Rpc.call_uint(stake_token, Abi.encode_erc20("balance_of", [wallet])),
         {:ok, usdc_balance} <-
           Rpc.call_uint(usdc, Abi.encode_erc20("balance_of", [wallet])),
         {:ok, staked} <-
           Rpc.call_uint(Abi.staking_address(), Abi.encode_read("staked_balance", [wallet])),
         {:ok, claimable_usdc} <-
           Rpc.call_uint(Abi.staking_address(), Abi.encode_read("claimable_usdc", [wallet])),
         {:ok, claimable_regent} <-
           Rpc.call_uint(Abi.staking_address(), Abi.encode_read("claimable_regent", [wallet])),
         {:ok, funded_regent} <-
           Rpc.call_uint(
             Abi.staking_address(),
             Abi.encode_read("funded_claimable_regent", [wallet])
           ) do
      {:ok,
       %{
         wallet_address: wallet,
         wallet_token_balance_raw: Integer.to_string(token_balance),
         wallet_token_balance: Rpc.format_units(token_balance, 18),
         wallet_usdc_balance_raw: Integer.to_string(usdc_balance),
         wallet_usdc_balance: Rpc.format_units(usdc_balance, 6),
         wallet_stake_balance_raw: Integer.to_string(staked),
         wallet_stake_balance: Rpc.format_units(staked, 18),
         wallet_claimable_usdc_raw: Integer.to_string(claimable_usdc),
         wallet_claimable_usdc: Rpc.format_units(claimable_usdc, 6),
         wallet_claimable_regent_raw: Integer.to_string(claimable_regent),
         wallet_claimable_regent: Rpc.format_units(claimable_regent, 18),
         wallet_funded_claimable_regent_raw: Integer.to_string(funded_regent),
         wallet_funded_claimable_regent: Rpc.format_units(funded_regent, 18)
       }}
    end
  end

  defp approval_field(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  defp normalize_or_nil(value) do
    Abi.normalize_address!(value)
  rescue
    _ -> nil
  end
end
