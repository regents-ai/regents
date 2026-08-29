defmodule AshPlatform.Autolaunch.LabPositionActions do
  @moduledoc false

  require Ash.Query

  alias AshPlatform.Accounts.SessionAuthority
  alias AshPlatform.Actors.{Human, System}
  alias AshPlatform.Autolaunch

  alias AshPlatform.Autolaunch.{
    Bid,
    Lab,
    LabAbi,
    LabProjection,
    LabRpc,
    LaunchJob
  }

  alias AshPlatform.WalletActions.{Abi, Address, Envelope, Rpc}

  @actor %System{}
  @domain AshPlatform.Autolaunch
  @resource "autolaunch_lab_position"
  @chain_id 31_337
  @kinds [:exit, :claim, :migrate]

  @doc "Finds the one locally projected bid owned by the selected wallet for an auction."
  def position(auction_id, address, opts) do
    with {:ok, actor} <- human(opts),
         {:ok, signer} <- current_wallet(address, actor, opts),
         {:ok, positions} <- Autolaunch.list_my_bid_positions(actor: actor),
         owned <-
           Enum.filter(positions, fn position ->
             position.auction_id == auction_id and Address.equal?(position.owner_address, signer) and
               is_binary(position.onchain_bid_id)
           end) do
      case owned do
        [] -> {:ok, %{bid: nil, signer: signer}}
        [bid] -> present_position(bid, signer)
        _more_than_one -> unavailable(:multiple_lab_positions)
      end
    end
  end

  @doc "Builds one signed local-only exit, claim, or migration transaction."
  def prepare(bid_id, address, kind, opts) when kind in @kinds do
    with {:ok, actor} <- human(opts),
         {:ok, signer} <- current_wallet(address, actor, opts),
         {:ok, bid} <- owned_bid(bid_id, signer, actor),
         {:ok, snapshot} <- snapshot(bid),
         :ok <- eligible(kind, snapshot),
         {:ok, envelope} <- envelope(kind, bid, signer, snapshot) do
      {:ok, %{operation: operation(envelope, kind, :prepared, nil, nil)}}
    end
  end

  def prepare(_bid_id, _address, _kind, _opts), do: unavailable(:unknown_lab_position_action)

  @doc "Revalidates the selected account, exact config, code, and eligibility before dispatch."
  def claim_dispatch(%{envelope: envelope} = operation, address, opts) do
    kind = operation.kind

    with true <- kind in @kinds,
         {:ok, actor} <- human(opts),
         {:ok, signer} <- current_wallet(address, actor, opts),
         true <- Address.equal?(signer, envelope["expected_signer"]),
         true <- valid_envelope?(envelope, kind),
         true <- Lab.binding_matches?(envelope["metadata"]["lab"], [:strategy]),
         {:ok, bid} <- owned_bid(envelope["arguments"]["bid_id"], signer, actor),
         :ok <- bound_bid?(bid, envelope),
         {:ok, snapshot} <- snapshot(bid),
         :ok <- bound_snapshot?(snapshot, envelope),
         :ok <- eligible(kind, snapshot) do
      {:ok, %{operation: operation(envelope, kind, :dispatched, nil, nil)}}
    else
      false -> unavailable(:lab_config_changed)
      {:error, reason} -> unavailable(reason)
    end
  end

  @doc "Verifies one local receipt and applies its readbacks transactionally."
  def verify(%{envelope: envelope, kind: kind}, hash, opts) do
    with true <- kind in @kinds,
         {:ok, actor} <- human(opts),
         {:ok, signer} <- current_wallet(envelope["expected_signer"], actor, opts),
         true <- valid_confirmation_envelope?(envelope, kind),
         true <- Lab.binding_matches?(envelope["metadata"]["lab"], [:strategy]),
         {:ok, bid} <- owned_bid(envelope["arguments"]["bid_id"], signer, actor),
         :ok <- bound_bid?(bid, envelope),
         {:ok, config} <- Lab.current(),
         {:ok, outcome} <- LabRpc.canonical_outcome(config, envelope, step(envelope), hash),
         {:ok, verified} <- settled(kind, outcome, envelope, bid, config),
         :ok <- project_if_confirmed(bid, verified) do
      {:ok,
       %{
         operation:
           operation(
             envelope,
             kind,
             verified.state,
             hash,
             Map.get(verified, :result)
           )
       }}
    else
      false -> unavailable(:lab_config_changed)
      {:error, reason} -> unavailable(reason)
    end
  end

  defp present_position(bid, signer) do
    with {:ok, snapshot} <- snapshot(bid) do
      {:ok,
       %{
         bid: bid,
         signer: signer,
         current_block: snapshot.block.number,
         actions: %{
           exit: eligible?(:exit, snapshot),
           claim: eligible?(:claim, snapshot),
           migrate: eligible?(:migrate, snapshot)
         },
         status: position_status(snapshot)
       }}
    end
  end

  defp snapshot(%Bid{} = bid) do
    with {:ok, launch} <- launch_for(bid.auction_id),
         {:ok, config, block, opts} <- LabRpc.current([:strategy]),
         :ok <- LabRpc.ensure_contract(bid.auction_address, block, opts),
         {:ok, bid_words} <-
           LabRpc.call_words(
             config,
             bid.auction_address,
             "auction",
             "bids(uint256)",
             [String.to_integer(bid.onchain_bid_id)],
             7,
             block,
             opts
           ),
         {:ok, start_block} <-
           LabRpc.call_uint(
             config,
             bid.auction_address,
             "auction",
             "startBlock()",
             [],
             block,
             opts
           ),
         {:ok, end_block} <-
           LabRpc.call_uint(config, bid.auction_address, "auction", "endBlock()", [], block, opts),
         {:ok, claim_block} <-
           LabRpc.call_uint(
             config,
             bid.auction_address,
             "auction",
             "claimBlock()",
             [],
             block,
             opts
           ),
         {:ok, graduated} <-
           call_bool(config, bid.auction_address, "isGraduated()", block, opts),
         {:ok, clearing_price} <-
           LabRpc.call_uint(
             config,
             bid.auction_address,
             "auction",
             "clearingPrice()",
             [],
             block,
             opts
           ),
         {:ok, distribution} <-
           LabRpc.words(
             config,
             :strategy,
             "distribution(address)",
             [bid.auction_address],
             18,
             block,
             opts
           ),
         {:ok, owner} <- word_address(Enum.at(bid_words, 4)),
         {:ok, subject} <- word_address(Enum.at(distribution, 11)),
         true <- Address.equal?(owner, bid.owner_address),
         true <- Address.equal?(subject, launch.token_address),
         true <- Enum.at(distribution, 1) == start_block,
         true <- Enum.at(distribution, 2) == end_block,
         true <- Enum.at(distribution, 3) == claim_block do
      {:ok,
       %{
         bid: bid,
         launch: launch,
         config: config,
         block: block,
         owner: owner,
         subject: subject,
         bid_start_block: Enum.at(bid_words, 0),
         exited_block: Enum.at(bid_words, 2),
         max_price: Enum.at(bid_words, 3),
         tokens_filled: Enum.at(bid_words, 6),
         start_block: start_block,
         end_block: end_block,
         claim_block: claim_block,
         graduated: graduated,
         clearing_price: clearing_price,
         lifecycle: Enum.at(distribution, 0),
         migration_block: Enum.at(distribution, 4),
         treasury: word_address!(Enum.at(distribution, 13)),
         splitter: optional_address(Enum.at(distribution, 14)),
         receiver: optional_address(Enum.at(distribution, 15)),
         pool_id: word_hex(Enum.at(distribution, 16)),
         lp_token_id: Enum.at(distribution, 17)
       }}
    else
      false -> unavailable(:lab_position_mismatch)
      :error -> unavailable(:invalid_chain_response)
      {:error, reason} -> unavailable(reason)
      _other -> unavailable(:invalid_chain_response)
    end
  end

  defp eligible(:exit, snapshot) do
    cond do
      snapshot.block.number < snapshot.end_block ->
        unavailable(:auction_not_finished)

      snapshot.exited_block != 0 ->
        unavailable(:bid_already_exited)

      snapshot.graduated and snapshot.max_price <= snapshot.clearing_price ->
        unavailable(:partial_fill_unsupported)

      true ->
        :ok
    end
  end

  defp eligible(:claim, snapshot) do
    cond do
      snapshot.block.number < snapshot.claim_block -> unavailable(:claim_not_open)
      not snapshot.graduated -> unavailable(:auction_not_graduated)
      snapshot.exited_block == 0 -> unavailable(:bid_not_exited)
      snapshot.tokens_filled == 0 -> unavailable(:nothing_to_claim)
      true -> :ok
    end
  end

  defp eligible(:migrate, snapshot) do
    cond do
      snapshot.lifecycle != 1 -> unavailable(:migration_not_available)
      snapshot.block.number < snapshot.migration_block -> unavailable(:migration_not_open)
      true -> :ok
    end
  end

  defp eligible?(kind, snapshot), do: eligible(kind, snapshot) == :ok

  defp envelope(kind, bid, signer, snapshot) do
    {action, contract_name, target, data, risk} = transaction(kind, bid, snapshot)

    envelope =
      Envelope.new(action, signer, data,
        to: target,
        resource: @resource,
        contract_name: contract_name,
        chain_id: @chain_id,
        lab_binding: Lab.binding(snapshot.config, [:strategy]),
        risk_copy: risk,
        arguments: %{
          "kind" => Atom.to_string(kind),
          "bid_id" => bid.bid_id,
          "auction_id" => bid.auction_id,
          "auction" => bid.auction_address,
          "onchain_bid_id" => bid.onchain_bid_id,
          "subject" => snapshot.subject,
          "token_name" => snapshot.launch.token_name,
          "token_symbol" => snapshot.launch.token_symbol,
          "treasury" => snapshot.treasury,
          "reviewed_block_number" => snapshot.block.number,
          "reviewed_block_hash" => snapshot.block.hash,
          "steps" => [%{"step" => Atom.to_string(kind), "to" => target, "data" => data}]
        }
      )
      |> stored()

    {:ok, envelope}
  rescue
    _ -> unavailable(:lab_position_unavailable)
  end

  defp transaction(:exit, bid, snapshot) do
    data =
      LabAbi.encode(snapshot.config.abis["auction"], "exitBid(uint256)", [
        String.to_integer(bid.onchain_bid_id)
      ])

    {"exit_bid", "IContinuousClearingAuction", bid.auction_address, data,
     "Your wallet exits this exact bid on the local Base fork. Test assets have no mainnet value."}
  end

  defp transaction(:claim, bid, snapshot) do
    data =
      LabAbi.encode(snapshot.config.abis["auction"], "claimTokens(uint256)", [
        String.to_integer(bid.onchain_bid_id)
      ])

    {"claim_bid_tokens", "IContinuousClearingAuction", bid.auction_address, data,
     "Your wallet claims this exact bid's local test tokens. They have no mainnet value."}
  end

  defp transaction(:migrate, bid, snapshot) do
    data =
      LabAbi.encode(snapshot.config.abis["strategy"], "migrate(address)", [bid.auction_address])

    {"migrate_launch", "RegentLBPStrategy", Lab.address!(snapshot.config, :strategy), data,
     "Your wallet triggers this launch's permissionless local-fork migration. Test assets have no mainnet value."}
  end

  defp settled(_kind, :pending, _envelope, _bid, _config), do: {:ok, %{state: :submitted}}
  defp settled(_kind, :reverted, _envelope, _bid, _config), do: {:ok, %{state: :reverted}}

  defp settled(:exit, {:success, logs}, envelope, _bid, config) do
    signature = "BidExited(uint256,address,uint256,uint256)"
    bid_id = integer(envelope, "onchain_bid_id")

    with {:ok, block} <- LabRpc.block_from_logs(logs),
         {:ok, {[^bid_id, owner_word], [tokens_filled, refunded]}} <-
           LabAbi.event_words(config.abis["auction"], signature, logs, envelope["to"]),
         {:ok, owner} <- word_address(owner_word),
         true <- Address.equal?(owner, envelope["expected_signer"]),
         opts <- LabRpc.opts(config),
         {:ok, words} <-
           LabRpc.call_words(
             config,
             envelope["to"],
             "auction",
             "bids(uint256)",
             [bid_id],
             7,
             block,
             opts
           ),
         true <- Enum.at(words, 2) > 0,
         true <- Enum.at(words, 6) == tokens_filled,
         {:ok, clearing_price} <-
           LabRpc.call_uint(
             config,
             envelope["to"],
             "auction",
             "clearingPrice()",
             [],
             block,
             opts
           ) do
      {:ok,
       %{
         state: :confirmed,
         result: %{
           "bid_status" => "exited",
           "exited" => true,
           "claimed" => false,
           "tokens_filled_atomic" => Integer.to_string(tokens_filled),
           "currency_refunded_atomic" => Integer.to_string(refunded),
           "current_clearing_price" => Rpc.format_units(clearing_price, 18),
           "local_block_hash" => block.hash
         }
       }}
    else
      false -> {:ok, %{state: :unverified}}
      :error -> {:ok, %{state: :unverified}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp settled(:claim, {:success, logs}, envelope, _bid, config) do
    signature = "TokensClaimed(uint256,address,uint256)"
    bid_id = integer(envelope, "onchain_bid_id")

    with {:ok, block} <- LabRpc.block_from_logs(logs),
         {:ok, {[^bid_id, owner_word], [tokens_filled]}} <-
           LabAbi.event_words(config.abis["auction"], signature, logs, envelope["to"]),
         true <- tokens_filled > 0,
         {:ok, owner} <- word_address(owner_word),
         true <- Address.equal?(owner, envelope["expected_signer"]),
         opts <- LabRpc.opts(config),
         {:ok, words} <-
           LabRpc.call_words(
             config,
             envelope["to"],
             "auction",
             "bids(uint256)",
             [bid_id],
             7,
             block,
             opts
           ),
         true <- Enum.at(words, 6) == 0,
         {:ok, clearing_price} <-
           LabRpc.call_uint(
             config,
             envelope["to"],
             "auction",
             "clearingPrice()",
             [],
             block,
             opts
           ) do
      {:ok,
       %{
         state: :confirmed,
         result: %{
           "bid_status" => "claimed",
           "exited" => true,
           "claimed" => true,
           "tokens_claimed_atomic" => Integer.to_string(tokens_filled),
           "current_clearing_price" => Rpc.format_units(clearing_price, 18),
           "local_block_hash" => block.hash
         }
       }}
    else
      false -> {:ok, %{state: :unverified}}
      :error -> {:ok, %{state: :unverified}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp settled(:migrate, {:success, logs}, envelope, _bid, config) do
    with {:ok, block} <- LabRpc.block_from_logs(logs),
         {:ok, result} <- migration_result(logs, envelope, config, block) do
      {:ok, %{state: :confirmed, result: Map.put(result, "local_block_hash", block.hash)}}
    else
      :error -> {:ok, %{state: :unverified}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp migration_result(logs, envelope, config, block) do
    auction = envelope["arguments"]["auction"]
    subject = envelope["arguments"]["subject"]
    opts = LabRpc.opts(config)

    with {:ok, distribution} <-
           LabRpc.words(
             config,
             :strategy,
             "distribution(address)",
             [auction],
             18,
             block,
             opts
           ),
         true <- Enum.at(distribution, 0) in [2, 3],
         {:ok, recorded_subject} <- word_address(Enum.at(distribution, 11)),
         true <- Address.equal?(recorded_subject, subject) do
      migration_event(logs, envelope, config, distribution)
    else
      false -> :error
      :error -> :error
      {:error, reason} -> {:error, reason}
    end
  end

  defp migration_event(logs, envelope, config, [2 | _] = distribution) do
    signature =
      "LaunchGraduated(address,address,bytes32,address,address,uint160,uint256,uint128,uint128)"

    with {:ok,
          {[auction_word, subject_word, pool_id],
           [splitter_word, receiver_word, sqrt_price, lp_token_id, lp_regent, lp_subject]}} <-
           LabAbi.event_words(
             config.abis["strategy"],
             signature,
             logs,
             Lab.address!(config, :strategy)
           ),
         {:ok, auction} <- word_address(auction_word),
         {:ok, subject} <- word_address(subject_word),
         {:ok, splitter} <- word_address(splitter_word),
         {:ok, receiver} <- word_address(receiver_word),
         true <- Address.equal?(auction, envelope["arguments"]["auction"]),
         true <- Address.equal?(subject, envelope["arguments"]["subject"]),
         true <- Enum.at(distribution, 0) == 2,
         true <- Enum.at(distribution, 9) == sqrt_price,
         true <- Enum.at(distribution, 17) == lp_token_id,
         true <- Enum.at(distribution, 7) == lp_regent,
         true <- Enum.at(distribution, 8) == lp_subject,
         true <- Address.equal?(word_address!(Enum.at(distribution, 14)), splitter),
         true <- Address.equal?(word_address!(Enum.at(distribution, 15)), receiver),
         true <- Enum.at(distribution, 16) == pool_id do
      {:ok,
       %{
         "auction_state" => "graduated",
         "subject" => subject,
         "splitter" => splitter,
         "receiver" => receiver,
         "pool_id" => word_hex(pool_id),
         "lp_token_id" => Integer.to_string(lp_token_id),
         "token_symbol" => envelope["arguments"]["token_symbol"]
       }}
    else
      _ -> :error
    end
  end

  defp migration_event(logs, envelope, config, [3 | _] = distribution) do
    signature = "LaunchRetired(address,address,uint128)"

    with {:ok, {[auction_word, subject_word], [reserve_returned]}} <-
           LabAbi.event_words(
             config.abis["strategy"],
             signature,
             logs,
             Lab.address!(config, :strategy)
           ),
         {:ok, auction} <- word_address(auction_word),
         {:ok, subject} <- word_address(subject_word),
         true <- Address.equal?(auction, envelope["arguments"]["auction"]),
         true <- Address.equal?(subject, envelope["arguments"]["subject"]),
         true <- Enum.at(distribution, 0) == 3,
         true <- Enum.at(distribution, 6) == reserve_returned do
      {:ok,
       %{
         "auction_state" => "failed",
         "subject" => subject,
         "reserve_returned_atomic" => Integer.to_string(reserve_returned)
       }}
    else
      _ -> :error
    end
  end

  defp migration_event(_logs, _envelope, _config, _distribution), do: :error

  defp project_if_confirmed(bid, %{state: :confirmed, result: result}),
    do: LabProjection.project_position(bid, result)

  defp project_if_confirmed(_bid, _unsettled), do: :ok

  defp valid_envelope?(envelope, kind) do
    Envelope.valid?(envelope,
      resource: @resource,
      action: action(kind),
      chain_id: @chain_id,
      signer: envelope["expected_signer"],
      to: step(envelope)["to"],
      contract_name: contract_name(kind)
    )
  end

  defp valid_confirmation_envelope?(envelope, kind) do
    Envelope.valid_for_confirmation?(envelope,
      resource: @resource,
      action: action(kind),
      chain_id: @chain_id,
      signer: envelope["expected_signer"],
      to: step(envelope)["to"],
      contract_name: contract_name(kind)
    )
  end

  defp bound_bid?(bid, envelope) do
    arguments = envelope["arguments"]

    if bid.auction_id == arguments["auction_id"] and
         Address.equal?(bid.auction_address, arguments["auction"]) and
         bid.onchain_bid_id == arguments["onchain_bid_id"] and
         Address.equal?(bid.owner_address, envelope["expected_signer"]),
       do: :ok,
       else: unavailable(:lab_position_changed)
  end

  defp bound_snapshot?(snapshot, envelope) do
    arguments = envelope["arguments"]

    if Address.equal?(snapshot.subject, arguments["subject"]) and
         Address.equal?(snapshot.treasury, arguments["treasury"]),
       do: :ok,
       else: unavailable(:lab_position_changed)
  end

  defp owned_bid(bid_id, signer, actor) do
    case Autolaunch.get_my_bid_position(bid_id, actor: actor) do
      {:ok, nil} -> unavailable(:lab_position_not_found)
      {:ok, bid} -> if Address.equal?(bid.owner_address, signer), do: {:ok, bid}, else: denied()
      _error -> unavailable(:lab_position_not_found)
    end
  end

  defp launch_for(auction_id) do
    LaunchJob
    |> Ash.Query.new(domain: @domain)
    |> Ash.Query.filter(auction_id == ^auction_id)
    |> Ash.read_one(domain: @domain, actor: @actor)
    |> case do
      {:ok, nil} -> unavailable(:lab_launch_not_found)
      result -> result
    end
  end

  defp current_wallet(address, %Human{human_account_id: human_id}, opts) do
    with {:ok, signer} <- normalize(address),
         %{lineage: lineage, account_id: ^human_id} <- lease(opts),
         %{wallet_addresses: wallets} <- SessionAuthority.leased_account(lineage, human_id),
         true <- Enum.any?(wallets || [], &Address.equal?(&1, signer)) do
      {:ok, signer}
    else
      false -> unavailable(:wrong_signer)
      _ -> unavailable(:session_unavailable)
    end
  end

  defp human(opts) do
    case Keyword.get(opts, :actor) do
      %Human{} = actor -> {:ok, actor}
      _other -> unavailable(:authentication_required)
    end
  end

  defp lease(opts) do
    case get_in(opts, [:context, :session_lease]) do
      %{lineage: lineage, account_id: account_id}
      when is_binary(lineage) and is_integer(account_id) ->
        %{lineage: lineage, account_id: account_id}

      _missing ->
        nil
    end
  end

  defp call_bool(config, address, signature, block, opts) do
    Rpc.call_bool(
      address,
      LabAbi.encode(config.abis["auction"], signature, []),
      block,
      opts
    )
  end

  defp operation(envelope, kind, state, hash, result) do
    %{
      action_id: envelope["action_id"],
      signer: envelope["expected_signer"],
      kind: kind,
      state: state,
      envelope: envelope,
      transaction_hash: hash,
      result: result,
      terminal_at: if(state in [:confirmed, :reverted, :unverified], do: DateTime.utc_now())
    }
  end

  defp step(envelope), do: envelope["arguments"]["steps"] |> List.first()
  defp integer(envelope, key), do: envelope["arguments"][key] |> String.to_integer()
  defp stored(envelope), do: envelope |> Jason.encode!() |> Jason.decode!()

  defp action(:exit), do: "exit_bid"
  defp action(:claim), do: "claim_bid_tokens"
  defp action(:migrate), do: "migrate_launch"

  defp contract_name(kind) when kind in [:exit, :claim], do: "IContinuousClearingAuction"
  defp contract_name(:migrate), do: "RegentLBPStrategy"

  defp position_status(%{lifecycle: lifecycle}) when lifecycle in [2, 3], do: :terminal

  defp position_status(%{block: %{number: block}, migration_block: migration})
       when block >= migration,
       do: :migration_ready

  defp position_status(%{
         block: %{number: block},
         tokens_filled: tokens,
         exited_block: exited,
         claim_block: claim
       })
       when tokens > 0 and exited > 0 and block >= claim,
       do: :claim_ready

  defp position_status(%{block: %{number: block}, end_block: ending, exited_block: 0})
       when block >= ending,
       do: :exit_ready

  defp position_status(%{block: %{number: block}, start_block: start}) when block < start,
    do: :countdown

  defp position_status(%{block: %{number: block}, end_block: ending}) when block < ending,
    do: :auction

  defp position_status(_snapshot), do: :waiting

  defp normalize(value) do
    case Address.normalize(value) do
      {:ok, address} -> {:ok, address}
      :error -> unavailable(:invalid_address)
    end
  end

  defp word_address(value) do
    case Abi.word_address(value) do
      {:ok, address} -> {:ok, address}
      :error -> unavailable(:invalid_chain_response)
    end
  end

  defp word_address!(value) do
    {:ok, address} = word_address(value)
    address
  end

  defp optional_address(0), do: nil
  defp optional_address(value), do: word_address!(value)

  defp word_hex(value),
    do: "0x" <> (value |> Integer.to_string(16) |> String.pad_leading(64, "0"))

  defp denied, do: unavailable(:wrong_signer)
  defp unavailable(reason), do: {:error, reason}
end
