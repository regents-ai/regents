defmodule AshPlatform.Redemption.RpcClient do
  @moduledoc false
  @behaviour AshPlatform.Redemption.ChainClient

  alias AshPlatform.WalletActions.{Abi, Envelope, RedemptionAbi, Rpc}

  @chain_id 8453
  @actions ~w(approve_nft_collection approve_exact_usdc redeem claim)
  @rpc_opts [client_key: :redemption_http_client, log_scope: "redemption"]

  @impl true
  def overview(wallet, collection, token_id) do
    task = Task.async(fn -> do_overview(wallet, collection, token_id) end)
    overview_timeout = Application.get_env(:ash_platform, :redemption_overview_timeout, 12_000)

    case Task.yield(task, overview_timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      _timeout -> {:error, :chain_timeout}
    end
  end

  @impl true
  def confirm(envelope, transaction_hash) do
    with {:ok, target, contract_name} <- RedemptionAbi.action_identity(envelope),
         true <- valid_for_confirmation?(envelope, target, contract_name),
         true <- Rpc.valid_hash?(transaction_hash),
         {:ok, block} <- Rpc.safe_block(@rpc_opts),
         {:ok, outcome} <-
           Rpc.canonical_outcome(
             transaction_hash,
             envelope.expected_signer,
             target,
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

  # The exact collection approval and the exact 80 USDC allowance, taken fresh
  # immediately before the Redeem dispatch is claimed and never required again.
  # A collection that is no longer approved is its own refusal and is never
  # reported as a USDC failure.
  @impl true
  def approval_current(%{action: "redeem", expected_signer: signer, arguments: arguments}) do
    redeemer = normalized(RedemptionAbi.redeemer_address())
    usdc = normalized(RedemptionAbi.usdc_address())
    price = String.to_integer(RedemptionAbi.price_atomic())

    with {:ok, collection} <- selected_collection(field(arguments, :collection)),
         {:ok, block} <- Rpc.safe_block(@rpc_opts),
         {:ok, true} <- approved_for_all(collection, signer, redeemer, block),
         {:ok, ^price} <- allowance(usdc, signer, redeemer, block) do
      :ok
    else
      {:ok, false} -> {:error, :nft_approval_required}
      {:error, reason} -> {:error, reason}
      _changed -> {:error, :exact_usdc_approval_required}
    end
  end

  def approval_current(_envelope), do: :ok

  # The exact receipt and the exact action event together are the whole proof.
  # The page reads its own current snapshot after this verdict is durable, so
  # nothing mutable is read here.
  defp settled(envelope, hash, {:success, logs}) do
    case action_event(envelope, logs) do
      {:ok, event} -> Map.put(result(hash, :confirmed, nil), :event, event)
      :error -> result(hash, :unverified, :action_event_contradiction)
    end
  end

  defp settled(_envelope, hash, :reverted), do: result(hash, :reverted, :transaction_reverted)
  defp settled(_envelope, hash, :pending), do: result(hash, :pending, nil)

  defp result(hash, outcome, reason),
    do: %{
      transaction_hash: String.downcase(hash),
      outcome: outcome,
      reason: reason,
      event: %{}
    }

  # Each action's own immutable event, decoded against the deployed layout.
  defp action_event(
         %{action: "approve_nft_collection", expected_signer: signer, arguments: arguments},
         logs
       ) do
    redeemer = normalized(RedemptionAbi.redeemer_address())

    with {:ok, collection} <- selected_collection(field(arguments, :collection)),
         true <- RedemptionAbi.collection_approved?(logs, collection, signer, redeemer) do
      {:ok, %{}}
    else
      _contradiction -> :error
    end
  end

  defp action_event(%{action: "approve_exact_usdc", expected_signer: signer}, logs) do
    approved? =
      Abi.approval_recorded?(
        logs,
        normalized(RedemptionAbi.usdc_address()),
        signer,
        normalized(RedemptionAbi.redeemer_address()),
        String.to_integer(RedemptionAbi.price_atomic())
      )

    if approved?, do: {:ok, %{}}, else: :error
  end

  # `newId` is the mapped Regents Club token, never a USDC amount.
  defp action_event(%{action: "redeem", expected_signer: signer, arguments: arguments}, logs) do
    with {:ok, collection} <- selected_collection(field(arguments, :collection)),
         token_id when is_integer(token_id) <- field(arguments, :token_id),
         {:ok, result_token_id} <- RedemptionAbi.redeemed(logs, signer, collection, token_id) do
      {:ok, %{result_token_id: result_token_id}}
    else
      _contradiction -> :error
    end
  end

  defp action_event(%{action: "claim", expected_signer: signer}, logs) do
    with {:ok, amount} <- RedemptionAbi.claimed(logs, signer) do
      {:ok, %{claimed_raw: Integer.to_string(amount), claimed: Rpc.format_units(amount, 18)}}
    end
  end

  defp do_overview(wallet, collection, token_id) do
    redeemer = normalized(RedemptionAbi.redeemer_address())

    with {:ok, block} <- Rpc.safe_block(@rpc_opts),
         {:ok, animata_i} <- read_address("animata_i", redeemer, block),
         {:ok, animata_ii} <- read_address("animata_ii", redeemer, block),
         {:ok, result_collection} <- read_address("result_collection", redeemer, block),
         {:ok, usdc} <- read_address("usdc", redeemer, block),
         {:ok, regent} <- read_address("regent", redeemer, block),
         {:ok, price} <- read_uint("usdc_price", redeemer, block),
         {:ok, pure_price} <- read_uint("price", redeemer, block),
         {:ok, payout} <- read_uint("regent_payout", redeemer, block),
         {:ok, vest_duration} <- read_uint("vest_duration", redeemer, block),
         {:ok, max_token_id} <- read_uint("max_source_token_id", redeemer, block),
         :ok <-
           verify_constants(
             animata_i,
             animata_ii,
             result_collection,
             usdc,
             regent,
             price,
             pure_price,
             payout,
             vest_duration,
             max_token_id
           ),
         {:ok, account} <- account_reads(wallet, collection, token_id, usdc, redeemer, block) do
      {:ok,
       Map.merge(account, %{
         chain_id: @chain_id,
         chain_label: "Base",
         block_number: block.number,
         block_hash: block.hash,
         redeemer_address: redeemer,
         animata_i_address: animata_i,
         animata_ii_address: animata_ii,
         result_collection_address: result_collection,
         usdc_address: usdc,
         regent_address: regent,
         price_raw: Integer.to_string(price),
         price: Rpc.format_units(price, 6),
         payout_raw: Integer.to_string(payout),
         payout: Rpc.format_units(payout, 18),
         vest_duration_seconds: vest_duration
       })}
    end
  end

  defp account_reads(nil, nil, nil, _usdc, _redeemer, _block), do: {:ok, empty_account()}

  defp account_reads(wallet, collection, token_id, usdc, redeemer, block) do
    wallet = normalized(wallet)

    with :ok <- valid_selection(collection, token_id),
         {:ok, usdc_balance} <- balance_of(usdc, wallet, block),
         {:ok, usdc_allowance} <- allowance(usdc, wallet, redeemer, block),
         {:ok, claimable} <- read_uint("claimable", [wallet], redeemer, block),
         {:ok, [pool, released, claimed, start]} <-
           Rpc.call_words(
             redeemer,
             RedemptionAbi.encode_read("vest", [wallet]),
             block,
             4,
             @rpc_opts
           ),
         {:ok, token} <- token_reads(wallet, collection, token_id, redeemer, block) do
      {:ok,
       Map.merge(token, %{
         wallet_address: wallet,
         usdc_balance_raw: Integer.to_string(usdc_balance),
         usdc_balance: Rpc.format_units(usdc_balance, 6),
         usdc_allowance_raw: Integer.to_string(usdc_allowance),
         usdc_allowance: Rpc.format_units(usdc_allowance, 6),
         claimable_raw: Integer.to_string(claimable),
         claimable: Rpc.format_units(claimable, 18),
         vest_pool_raw: Integer.to_string(pool),
         vest_pool: Rpc.format_units(pool, 18),
         vest_released_raw: Integer.to_string(released),
         vest_released: Rpc.format_units(released, 18),
         vest_claimed_raw: Integer.to_string(claimed),
         vest_claimed: Rpc.format_units(claimed, 18),
         vest_start: start
       })}
    end
  end

  defp token_reads(_wallet, nil, nil, _redeemer, _block) do
    {:ok,
     %{
       selected_collection: nil,
       token_id: nil,
       nft_owner: nil,
       nft_owner_unavailable: false,
       nft_approved: nil,
       result_token_id: nil
     }}
  end

  defp token_reads(wallet, collection, nil, redeemer, block) do
    with {:ok, approved} <- approved_for_all(collection, wallet, redeemer, block) do
      {:ok,
       %{
         selected_collection: collection,
         token_id: nil,
         nft_owner: nil,
         nft_owner_unavailable: false,
         nft_approved: approved,
         result_token_id: nil
       }}
    end
  end

  defp token_reads(wallet, collection, token_id, redeemer, block) do
    with {:ok, approved} <- approved_for_all(collection, wallet, redeemer, block),
         {:ok, result_token_id} <-
           read_uint("result_token_id", [collection, token_id], redeemer, block) do
      {:ok,
       Map.merge(owner_read(collection, token_id, block), %{
         selected_collection: collection,
         token_id: token_id,
         nft_approved: approved,
         result_token_id: if(result_token_id == 0, do: nil, else: result_token_id)
       })}
    end
  end

  # The core account facts do not depend on the selected token, so an `ownerOf`
  # that cannot be read leaves them intact and says only that it is unknown. A
  # transport failure and a token that does not exist are indistinguishable here
  # and neither is reported as the other.
  defp owner_read(collection, token_id, block) do
    case Rpc.call_address(
           collection,
           RedemptionAbi.encode_erc721("owner_of", [token_id]),
           block,
           @rpc_opts
         ) do
      {:ok, owner} -> %{nft_owner: owner, nft_owner_unavailable: false}
      {:error, _unavailable} -> %{nft_owner: nil, nft_owner_unavailable: true}
    end
  end

  defp empty_account do
    %{
      wallet_address: nil,
      selected_collection: nil,
      token_id: nil,
      nft_owner: nil,
      nft_owner_unavailable: false,
      nft_approved: nil,
      usdc_balance_raw: nil,
      usdc_balance: nil,
      usdc_allowance_raw: nil,
      usdc_allowance: nil,
      claimable_raw: nil,
      claimable: nil,
      vest_pool_raw: nil,
      vest_pool: nil,
      vest_released_raw: nil,
      vest_released: nil,
      vest_claimed_raw: nil,
      vest_claimed: nil,
      vest_start: nil,
      result_token_id: nil
    }
  end

  defp verify_constants(
         animata_i,
         animata_ii,
         result_collection,
         usdc,
         regent,
         price,
         pure_price,
         payout,
         vest_duration,
         max_token_id
       ) do
    expected_price = String.to_integer(RedemptionAbi.price_atomic())
    expected_payout = String.to_integer(RedemptionAbi.payout_atomic())

    if animata_i == normalized(RedemptionAbi.animata_i_address()) and
         animata_ii == normalized(RedemptionAbi.animata_ii_address()) and
         result_collection == normalized(RedemptionAbi.result_collection_address()) and
         usdc == normalized(RedemptionAbi.usdc_address()) and
         regent == normalized(RedemptionAbi.regent_address()) and price == expected_price and
         pure_price == expected_price and payout == expected_payout and
         vest_duration == RedemptionAbi.vest_duration_seconds() and
         max_token_id == RedemptionAbi.max_token_id() do
      :ok
    else
      {:error, :contract_constants_mismatch}
    end
  end

  defp valid_selection(nil, nil), do: :ok

  defp valid_selection(collection, nil) when is_binary(collection) do
    if RedemptionAbi.collection_id(collection), do: :ok, else: {:error, :invalid_collection}
  end

  defp valid_selection(collection, token_id)
       when is_binary(collection) and is_integer(token_id) and token_id >= 1 and token_id <= 999 do
    if RedemptionAbi.collection_id(collection), do: :ok, else: {:error, :invalid_collection}
  end

  defp valid_selection(_collection, _token_id), do: {:error, :invalid_token_selection}

  defp selected_collection(collection) do
    if RedemptionAbi.collection_id(collection),
      do: {:ok, normalized(collection)},
      else: {:error, :invalid_collection}
  end

  defp valid_for_confirmation?(envelope, target, contract_name) do
    Envelope.valid_for_confirmation?(envelope,
      resource: "animata_redemption",
      to: target,
      signer: envelope.expected_signer,
      contract_name: contract_name,
      actions: @actions
    )
  end

  defp approved_for_all(collection, owner, operator, block),
    do:
      Rpc.call_bool(
        collection,
        RedemptionAbi.encode_erc721("is_approved_for_all", [owner, operator]),
        block,
        @rpc_opts
      )

  defp allowance(token, owner, spender, block),
    do:
      Rpc.call_uint(
        token,
        RedemptionAbi.encode_erc20("allowance", [owner, spender]),
        block,
        @rpc_opts
      )

  defp balance_of(token, wallet, block),
    do: Rpc.call_uint(token, RedemptionAbi.encode_erc20("balance_of", [wallet]), block, @rpc_opts)

  defp read_uint(id, target, block), do: read_uint(id, [], target, block)

  defp read_uint(id, arguments, target, block),
    do: Rpc.call_uint(target, RedemptionAbi.encode_read(id, arguments), block, @rpc_opts)

  defp read_address(id, target, block),
    do: Rpc.call_address(target, RedemptionAbi.encode_read(id), block, @rpc_opts)

  defp normalized(address), do: Abi.normalize_address!(address)
  defp field(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
