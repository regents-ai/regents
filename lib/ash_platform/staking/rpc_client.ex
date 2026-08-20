defmodule AshPlatform.Staking.RpcClient do
  @moduledoc false
  @behaviour AshPlatform.Staking.ChainClient

  alias AshPlatform.WalletActions.{Abi, Address, Envelope, Rpc}

  @overview_timeout 12_000
  @chain_id 8453
  @resource "regent_staking"
  @contract_name "RegentRevenueStaking"
  @actions ~w(stake unstake claim_usdc claim_regent claim_and_restake_regent)
  @rpc_opts [client_key: :staking_http_client, log_scope: "staking"]

  @impl true
  def overview(wallet_address) do
    task = Task.async(fn -> do_overview(wallet_address) end)

    case Task.yield(task, @overview_timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      _timeout -> {:error, :chain_timeout}
    end
  end

  # One `safe` block owns every read below it. A partial read is unavailable, so
  # nothing on the page can pair one block's balance with another's total.
  defp do_overview(wallet_address) do
    with {:ok, block} <- Rpc.safe_block(@rpc_opts),
         {:ok, paused} <- read_bool("paused", block),
         {:ok, total_staked} <- read_uint("total_staked", block),
         {:ok, denominator} <-
           Rpc.call_uint(
             Abi.staking_address(),
             Abi.encode_supply_denominator(),
             block,
             @rpc_opts
           ),
         {:ok, stake_token} <- read_address("stake_token", block),
         {:ok, usdc} <- read_address("usdc", block),
         true <- stake_token == Abi.normalize_address!(Abi.stake_token_address()),
         true <- usdc == Abi.normalize_address!(Abi.usdc_address()),
         {:ok, account} <- account_reads(wallet_address, stake_token, usdc, block) do
      capacity = max(denominator - total_staked, 0)

      {:ok,
       Map.merge(account, %{
         chain_id: @chain_id,
         chain_label: "Base",
         block_number: block.number,
         block_hash: block.hash,
         contract_address: Abi.normalize_address!(Abi.staking_address()),
         stake_token_address: stake_token,
         usdc_address: usdc,
         paused: paused,
         total_staked_raw: Integer.to_string(total_staked),
         total_staked: Rpc.format_units(total_staked, 18),
         supply_denominator_raw: Integer.to_string(denominator),
         remaining_capacity_raw: Integer.to_string(capacity),
         remaining_capacity: Rpc.format_units(capacity, 18)
       })}
    else
      false -> {:error, :contract_constants_mismatch}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def confirm(envelope, transaction_hash) do
    with true <- valid_for_confirmation?(envelope),
         true <- Rpc.valid_hash?(transaction_hash),
         {:ok, block} <- Rpc.safe_block(@rpc_opts),
         {:ok, outcome} <-
           Rpc.canonical_outcome(
             transaction_hash,
             envelope.expected_signer,
             envelope.to,
             envelope.data,
             block,
             @rpc_opts
           ) do
      {:ok, settled(envelope, transaction_hash, outcome)}
    else
      false -> {:error, :invalid_confirmation}
      {:error, reason} -> {:error, reason}
    end
  end

  # The exact receipt and the exact action event together are the whole proof. A
  # later mutable balance cannot replace them and is not consulted here at all:
  # the page reads its own current snapshot after this verdict is durable.
  defp settled(envelope, hash, {:success, logs}) do
    if action_event?(envelope, logs),
      do: result(hash, :confirmed, nil),
      else: result(hash, :unverified, :action_event_contradiction)
  end

  defp settled(_envelope, hash, :reverted), do: result(hash, :reverted, :transaction_reverted)
  defp settled(_envelope, hash, :pending), do: result(hash, :pending, nil)

  defp result(hash, outcome, reason),
    do: %{transaction_hash: String.downcase(hash), outcome: outcome, reason: reason}

  defp action_event?(%{action: "stake", arguments: arguments}, logs),
    do: Abi.stake_updated?(logs, normalize_or_nil(field(arguments, :receiver)))

  defp action_event?(%{action: "unstake", expected_signer: signer}, logs),
    do: Abi.stake_updated?(logs, signer)

  defp action_event?(%{action: "claim_usdc", expected_signer: signer}, logs),
    do: Abi.reward_claimed?(logs, :usdc_reward_claimed, signer)

  defp action_event?(%{action: "claim_regent", expected_signer: signer}, logs),
    do: Abi.reward_claimed?(logs, :reward_token_claimed, signer)

  defp action_event?(%{action: "claim_and_restake_regent", expected_signer: signer}, logs),
    do: Abi.reward_compounded?(logs, signer)

  @impl true
  def approval_status(%{approval: approval, expected_signer: signer} = envelope, hash)
      when is_map(approval) do
    with true <- valid_for_confirmation?(envelope),
         true <- Rpc.valid_hash?(hash),
         {:ok, token, spender, amount} <- approval_identity(approval),
         {:ok, block} <- Rpc.safe_block(@rpc_opts),
         {:ok, outcome} <-
           Rpc.canonical_outcome(
             hash,
             signer,
             token,
             field(approval, :data),
             block,
             @rpc_opts
           ) do
      {:ok, approval_outcome(outcome, token, signer, spender, amount)}
    else
      false -> {:error, :invalid_approval_confirmation}
      :error -> {:error, :invalid_approval_confirmation}
      {:error, reason} -> {:error, reason}
    end
  end

  def approval_status(_envelope, _hash), do: {:error, :invalid_approval_confirmation}

  # The approval's own event completes the approval transaction. Allowance is
  # globally mutable, so it is never what says this transaction happened.
  defp approval_outcome({:success, logs}, token, signer, spender, amount) do
    if Abi.approval_recorded?(logs, token, signer, spender, amount),
      do: :confirmed,
      else: :unverified
  end

  defp approval_outcome(outcome, _token, _signer, _spender, _amount), do: outcome

  # The exact allowance is required here, immediately before the stake claims its
  # dispatch, and never again afterwards: `transferFrom` legitimately spends it.
  @impl true
  def approval_current(%{approval: nil}), do: :ok

  def approval_current(%{approval: approval, expected_signer: signer}) do
    with {:ok, token, spender, amount} <- approval_identity(approval),
         {:ok, block} <- Rpc.safe_block(@rpc_opts),
         {:ok, allowance} <-
           Rpc.call_uint(
             token,
             Abi.encode_erc20("allowance", [signer, spender]),
             block,
             @rpc_opts
           ),
         ^amount <- allowance do
      :ok
    else
      {:error, reason} -> {:error, reason}
      _changed -> {:error, :approval_allowance_mismatch}
    end
  end

  # `allowance(owner, staking)` for the manifest REGENT token and nothing else:
  # a different token or spender is not this approval at all.
  defp approval_identity(approval) do
    token = normalize_or_nil(field(approval, :token))
    spender = normalize_or_nil(field(approval, :spender))

    with true <- Address.equal?(token, Abi.stake_token_address()),
         true <- Address.equal?(spender, Abi.staking_address()),
         {amount, ""} <- Integer.parse(field(approval, :amount) || "") do
      {:ok, token, spender, amount}
    else
      _mismatch -> :error
    end
  end

  defp account_reads(nil, _stake_token, _usdc, _block) do
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

  defp account_reads(wallet_address, stake_token, usdc, block) do
    wallet = Abi.normalize_address!(wallet_address)

    with {:ok, token_balance} <- balance_of(stake_token, wallet, block),
         {:ok, usdc_balance} <- balance_of(usdc, wallet, block),
         {:ok, staked} <- read_uint("staked_balance", [wallet], block),
         {:ok, claimable_usdc} <- read_uint("claimable_usdc", [wallet], block),
         {:ok, claimable_regent} <- read_uint("claimable_regent", [wallet], block),
         {:ok, funded_regent} <- read_uint("funded_claimable_regent", [wallet], block) do
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

  defp balance_of(token, wallet, block),
    do: Rpc.call_uint(token, Abi.encode_erc20("balance_of", [wallet]), block, @rpc_opts)

  defp read_uint(id, block), do: read_uint(id, [], block)

  defp read_uint(id, arguments, block),
    do: Rpc.call_uint(Abi.staking_address(), Abi.encode_read(id, arguments), block, @rpc_opts)

  defp read_bool(id, block),
    do: Rpc.call_bool(Abi.staking_address(), Abi.encode_read(id), block, @rpc_opts)

  defp read_address(id, block),
    do: Rpc.call_address(Abi.staking_address(), Abi.encode_read(id), block, @rpc_opts)

  defp field(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  defp valid_for_confirmation?(envelope) do
    Envelope.valid_for_confirmation?(envelope,
      resource: @resource,
      to: Abi.staking_address(),
      signer: envelope.expected_signer,
      contract_name: @contract_name,
      actions: @actions
    )
  end

  defp normalize_or_nil(value) do
    case Address.normalize(value) do
      {:ok, address} -> address
      :error -> nil
    end
  end
end
