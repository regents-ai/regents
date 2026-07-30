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
      _ -> {:error, :chain_timeout}
    end
  end

  @impl true
  def confirm(envelope, transaction_hash) do
    with {:ok, target, contract_name} <- identity_for(envelope),
         true <-
           Envelope.valid_for_confirmation?(envelope,
             resource: "animata_redemption",
             to: target,
             signer: envelope.expected_signer,
             contract_name: contract_name,
             actions: @actions
           ),
         :ok <- Rpc.verify_base_chain(@rpc_opts),
         :ok <-
           Rpc.confirmed_transaction(
             transaction_hash,
             envelope.expected_signer,
             target,
             envelope.data,
             @rpc_opts
           ) do
      confirmation_result(envelope, transaction_hash)
    else
      false -> {:error, :invalid_confirmation}
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_overview(wallet, collection, token_id) do
    redeemer = normalized(RedemptionAbi.redeemer_address())

    with :ok <- Rpc.verify_base_chain(@rpc_opts),
         {:ok, animata_i} <-
           Rpc.call_address(redeemer, RedemptionAbi.encode_read("animata_i"), @rpc_opts),
         {:ok, animata_ii} <-
           Rpc.call_address(redeemer, RedemptionAbi.encode_read("animata_ii"), @rpc_opts),
         {:ok, result_collection} <-
           Rpc.call_address(
             redeemer,
             RedemptionAbi.encode_read("result_collection"),
             @rpc_opts
           ),
         {:ok, usdc} <- Rpc.call_address(redeemer, RedemptionAbi.encode_read("usdc"), @rpc_opts),
         {:ok, regent} <-
           Rpc.call_address(redeemer, RedemptionAbi.encode_read("regent"), @rpc_opts),
         {:ok, price} <-
           Rpc.call_uint(redeemer, RedemptionAbi.encode_read("usdc_price"), @rpc_opts),
         {:ok, pure_price} <-
           Rpc.call_uint(redeemer, RedemptionAbi.encode_read("price"), @rpc_opts),
         {:ok, payout} <-
           Rpc.call_uint(redeemer, RedemptionAbi.encode_read("regent_payout"), @rpc_opts),
         {:ok, vest_duration} <-
           Rpc.call_uint(redeemer, RedemptionAbi.encode_read("vest_duration"), @rpc_opts),
         {:ok, max_token_id} <-
           Rpc.call_uint(redeemer, RedemptionAbi.encode_read("max_source_token_id"), @rpc_opts),
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
         {:ok, account} <- account_reads(wallet, collection, token_id, usdc, redeemer) do
      {:ok,
       Map.merge(account, %{
         chain_id: @chain_id,
         chain_label: "Base",
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
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp account_reads(nil, nil, nil, _usdc, _redeemer),
    do: {:ok, empty_account()}

  defp account_reads(wallet, collection, token_id, usdc, redeemer) do
    wallet = normalized(wallet)

    with :ok <- valid_selection(collection, token_id),
         {:ok, usdc_balance} <-
           Rpc.call_uint(usdc, RedemptionAbi.encode_erc20("balance_of", [wallet]), @rpc_opts),
         {:ok, usdc_allowance} <-
           Rpc.call_uint(
             usdc,
             RedemptionAbi.encode_erc20("allowance", [wallet, redeemer]),
             @rpc_opts
           ),
         {:ok, claimable} <-
           Rpc.call_uint(redeemer, RedemptionAbi.encode_read("claimable", [wallet]), @rpc_opts),
         {:ok, [pool, released, claimed, start]} <-
           Rpc.call_words(redeemer, RedemptionAbi.encode_read("vest", [wallet]), 4, @rpc_opts),
         {:ok, token} <- token_reads(wallet, collection, token_id, redeemer) do
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

  defp token_reads(_wallet, nil, nil, _redeemer) do
    {:ok,
     %{
       selected_collection: nil,
       token_id: nil,
       nft_owner: nil,
       nft_approved: nil,
       result_token_id: nil
     }}
  end

  defp token_reads(wallet, collection, nil, redeemer) do
    with {:ok, approved} <-
           Rpc.call_bool(
             collection,
             RedemptionAbi.encode_erc721("is_approved_for_all", [wallet, redeemer]),
             @rpc_opts
           ) do
      {:ok,
       %{
         selected_collection: collection,
         token_id: nil,
         nft_owner: nil,
         nft_approved: approved,
         result_token_id: nil
       }}
    end
  end

  defp token_reads(wallet, collection, token_id, redeemer) do
    with {:ok, owner} <-
           Rpc.call_address(
             collection,
             RedemptionAbi.encode_erc721("owner_of", [token_id]),
             @rpc_opts
           ),
         {:ok, approved} <-
           Rpc.call_bool(
             collection,
             RedemptionAbi.encode_erc721("is_approved_for_all", [wallet, redeemer]),
             @rpc_opts
           ),
         {:ok, result_token_id} <-
           Rpc.call_uint(
             redeemer,
             RedemptionAbi.encode_read("result_token_id", [collection, token_id]),
             @rpc_opts
           ) do
      {:ok,
       %{
         selected_collection: collection,
         token_id: token_id,
         nft_owner: owner,
         nft_approved: approved,
         result_token_id: if(result_token_id == 0, do: nil, else: result_token_id)
       }}
    end
  end

  defp empty_account do
    %{
      wallet_address: nil,
      selected_collection: nil,
      token_id: nil,
      nft_owner: nil,
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

  defp confirmation_result(envelope, transaction_hash) do
    collection = field(envelope.arguments, :collection)
    token_id = field(envelope.arguments, :token_id)

    case overview(envelope.expected_signer, collection, token_id) do
      {:ok, refreshed} ->
        refresh_error = postcondition(envelope.action, refreshed)

        {:ok,
         %{
           transaction_hash: String.downcase(transaction_hash),
           receipt_verified: true,
           redemption: refreshed,
           refresh_error: refresh_error
         }}

      {:error, reason} ->
        {:ok,
         %{
           transaction_hash: String.downcase(transaction_hash),
           receipt_verified: true,
           redemption: nil,
           refresh_error: reason
         }}
    end
  end

  defp postcondition("approve_nft_collection", %{nft_approved: true}), do: nil

  defp postcondition("approve_exact_usdc", %{usdc_allowance_raw: amount})
       when amount == "80000000",
       do: nil

  defp postcondition("redeem", %{result_token_id: token_id}) when is_integer(token_id), do: nil
  defp postcondition("claim", _refreshed), do: nil
  defp postcondition(_action, _refreshed), do: :chain_state_not_refreshed

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

  defp identity_for(%{action: "approve_nft_collection", arguments: arguments}) do
    collection = field(arguments, :collection)

    case RedemptionAbi.collection_id(collection) do
      "animata_i" -> {:ok, normalized(collection), "Animata I"}
      "animata_ii" -> {:ok, normalized(collection), "Animata II"}
      nil -> {:error, :invalid_collection}
    end
  end

  defp identity_for(%{action: "approve_exact_usdc"}),
    do: {:ok, normalized(RedemptionAbi.usdc_address()), "USDC"}

  defp identity_for(%{action: action}) when action in ["redeem", "claim"],
    do: {:ok, normalized(RedemptionAbi.redeemer_address()), "AnimataRedeemer"}

  defp identity_for(_envelope), do: {:error, :invalid_action}

  defp normalized(address), do: Abi.normalize_address!(address)
  defp field(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
