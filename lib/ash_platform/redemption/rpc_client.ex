defmodule AshPlatform.Redemption.RpcClient do
  @moduledoc false
  @behaviour AshPlatform.Redemption.ChainClient

  alias AshPlatform.WalletActions.{Abi, RedemptionAbi, Rpc}

  @chain_id 8453
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
         {:ok, [animata_i_held, animata_ii_held, regents_club_ready]} <-
           parallel_reads([
             fn -> balance_of(animata_i, redeemer, block) end,
             fn -> balance_of(animata_ii, redeemer, block) end,
             fn -> balance_of(result_collection, redeemer, block) end
           ]),
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
         vest_duration_seconds: vest_duration,
         max_source_token_id: max_token_id,
         animata_i_held_by_redeemer: animata_i_held,
         animata_ii_held_by_redeemer: animata_ii_held,
         regents_club_ready: regents_club_ready
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
       nft_approved: nil
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
         nft_approved: approved
       }}
    end
  end

  defp token_reads(wallet, collection, token_id, redeemer, block) do
    with {:ok, approved} <- approved_for_all(collection, wallet, redeemer, block) do
      {:ok,
       Map.merge(owner_read(collection, token_id, block), %{
         selected_collection: collection,
         token_id: token_id,
         nft_approved: approved
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
      vest_start: nil
    }
  end

  defp parallel_reads(reads) do
    timeout = Application.get_env(:ash_platform, :redemption_overview_timeout, 12_000)

    reads
    |> Task.async_stream(& &1.(),
      max_concurrency: length(reads),
      ordered: true,
      timeout: timeout,
      on_timeout: :kill_task
    )
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, {:ok, value}}, {:ok, values} -> {:cont, {:ok, [value | values]}}
      {:ok, {:error, reason}}, _ -> {:halt, {:error, reason}}
      _, _ -> {:halt, {:error, :chain_timeout}}
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
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
end
