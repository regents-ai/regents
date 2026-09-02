defmodule AshPlatform.Redemption.RpcClient do
  @moduledoc false
  @behaviour AshPlatform.Redemption.ChainClient

  alias AshPlatform.WalletActions.{Abi, RedemptionAbi, Rpc}

  @read_timeout 12_000
  @chain_id 8453
  @rpc_opts [client_key: :redemption_http_client, log_scope: "redemption"]

  @impl true
  def overview(wallet, collection, token_id),
    do: bounded(fn -> read({wallet, collection, token_id}) end)

  # One `latest` block owns every figure, and one aggregate returns them all:
  # the redeemer's constants proved against the pinned manifest, the three
  # collection counts, and the wallet's own account and approval facts. A
  # partial reading is unavailable, so nothing on the page can pair one block's
  # balance with another's allowance.
  defp read({wallet, collection, token_id}) do
    with {:ok, block} <- Rpc.latest_block(@rpc_opts),
         :ok <- identified_aggregator(block),
         {:ok, values} <-
           Rpc.aggregate3(aggregator(), calls(wallet, collection), block, @rpc_opts),
         {:ok, facts} <- facts(values, wallet, collection) do
      {:ok,
       facts
       |> Map.merge(owner(collection, token_id, block))
       |> Map.merge(%{
         chain_id: @chain_id,
         chain_label: "Base",
         block_number: block.number,
         block_hash: block.hash,
         redeemer_address: normalized(RedemptionAbi.redeemer_address()),
         selected_collection: collection,
         token_id: token_id
       })}
    end
  end

  defp facts(
         [
           animata_i,
           animata_ii,
           result_collection,
           usdc,
           regent,
           price,
           pure_price,
           payout,
           vest_duration,
           max_token_id,
           animata_i_held,
           animata_ii_held,
           regents_club_ready | account
         ],
         wallet,
         collection
       ) do
    with :ok <-
           verify_constants(
             [animata_i, animata_ii, result_collection, usdc, regent],
             [price, pure_price, payout, vest_duration, max_token_id]
           ) do
      {:ok,
       Map.merge(account_facts(account, wallet, collection), %{
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

  defp account_facts([], nil, _collection), do: blank_account()

  defp account_facts(
         [usdc_balance, usdc_allowance, claimable, [pool, released, claimed, start] | approval],
         wallet,
         _collection
       ) do
    %{
      wallet_address: wallet,
      nft_approved: approved(approval),
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
    }
  end

  defp approved([]), do: nil
  defp approved([approved]), do: approved

  # `ownerOf` reverts for a token that does not exist, which under the
  # aggregate's `allowFailure: false` would take every other figure down with
  # it, so the one read that may legitimately fail is made on its own against
  # the same block. A transport failure and a token that does not exist are
  # indistinguishable here and neither is reported as the other.
  defp owner(_collection, nil, _block), do: %{nft_owner: nil, nft_owner_unavailable: false}

  defp owner(collection, token_id, block) do
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

  defp blank_account do
    %{
      wallet_address: nil,
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

  defp calls(wallet, collection),
    do: protocol_calls() ++ account_calls(wallet) ++ approval_calls(wallet, collection)

  # The collection counts are read from the manifest's addresses, which the
  # same aggregate proves are the ones the redeemer names: a manifest that
  # disagreed with the contract would fail the whole reading.
  defp protocol_calls do
    redeemer = RedemptionAbi.redeemer_address()

    [
      {redeemer, RedemptionAbi.encode_read("animata_i"), :address},
      {redeemer, RedemptionAbi.encode_read("animata_ii"), :address},
      {redeemer, RedemptionAbi.encode_read("result_collection"), :address},
      {redeemer, RedemptionAbi.encode_read("usdc"), :address},
      {redeemer, RedemptionAbi.encode_read("regent"), :address},
      {redeemer, RedemptionAbi.encode_read("usdc_price"), :uint},
      {redeemer, RedemptionAbi.encode_read("price"), :uint},
      {redeemer, RedemptionAbi.encode_read("regent_payout"), :uint},
      {redeemer, RedemptionAbi.encode_read("vest_duration"), :uint},
      {redeemer, RedemptionAbi.encode_read("max_source_token_id"), :uint},
      {RedemptionAbi.animata_i_address(), RedemptionAbi.encode_erc20("balance_of", [redeemer]),
       :uint},
      {RedemptionAbi.animata_ii_address(), RedemptionAbi.encode_erc20("balance_of", [redeemer]),
       :uint},
      {RedemptionAbi.result_collection_address(),
       RedemptionAbi.encode_erc20("balance_of", [redeemer]), :uint}
    ]
  end

  # Under the aggregator every sub-call is made by the aggregator, so a read
  # about an account names that account in its own arguments and never relies
  # on who is calling.
  defp account_calls(nil), do: []

  defp account_calls(wallet) do
    redeemer = RedemptionAbi.redeemer_address()
    usdc = RedemptionAbi.usdc_address()

    [
      {usdc, RedemptionAbi.encode_erc20("balance_of", [wallet]), :uint},
      {usdc, RedemptionAbi.encode_erc20("allowance", [wallet, redeemer]), :uint},
      {redeemer, RedemptionAbi.encode_read("claimable", [wallet]), :uint},
      {redeemer, RedemptionAbi.encode_read("vest", [wallet]), {:words, 4}}
    ]
  end

  defp approval_calls(nil, _collection), do: []
  defp approval_calls(_wallet, nil), do: []

  defp approval_calls(wallet, collection) do
    operator = RedemptionAbi.redeemer_address()

    [
      {collection, RedemptionAbi.encode_erc721("is_approved_for_all", [wallet, operator]), :bool}
    ]
  end

  defp verify_constants(addresses, figures) do
    expected_addresses =
      Enum.map(
        [
          RedemptionAbi.animata_i_address(),
          RedemptionAbi.animata_ii_address(),
          RedemptionAbi.result_collection_address(),
          RedemptionAbi.usdc_address(),
          RedemptionAbi.regent_address()
        ],
        &normalized/1
      )

    price = String.to_integer(RedemptionAbi.price_atomic())

    expected_figures = [
      price,
      price,
      String.to_integer(RedemptionAbi.payout_atomic()),
      RedemptionAbi.vest_duration_seconds(),
      RedemptionAbi.max_token_id()
    ]

    if addresses == expected_addresses and figures == expected_figures,
      do: :ok,
      else: {:error, :contract_constants_mismatch}
  end

  defp aggregator, do: Abi.multicall3_address()

  defp identified_aggregator(block),
    do:
      Rpc.verified_runtime_code(
        aggregator(),
        Abi.multicall3_runtime_keccak256(),
        Abi.multicall3_runtime_bytes(),
        block,
        @rpc_opts
      )

  defp bounded(read) do
    task = Task.async(read)

    case Task.yield(task, @read_timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      _timeout -> {:error, :chain_timeout}
    end
  end

  defp normalized(address), do: Abi.normalize_address!(address)
end
