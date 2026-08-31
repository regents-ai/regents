defmodule AshPlatform.RegentsClub.RpcClient do
  @moduledoc false

  alias AshPlatform.RegentsClub
  alias AshPlatform.RegentsClub.Actions
  alias AshPlatform.WalletActions.{Address, Rpc}

  @rpc_opts [client_key: :regents_club_http_client, log_scope: "regents_club_metadata"]
  @scan_blocks 1024
  @non_owner "0x0000000000000000000000000000000000000001"
  @revert_codes [3, -32_000, -32_015]

  def readiness, do: Rpc.verify_base_chain(@rpc_opts)

  def status do
    with :ok <- readiness(),
         {:ok, block} <- Rpc.safe_block(@rpc_opts),
         {:ok, state} <- snapshot(block) do
      cond do
        ready?(state) -> {:ok, Map.put(state, :state, :ready)}
        complete?(state) -> {:ok, Map.put(state, :state, :changed_unverified)}
        true -> {:error, :contract_state_mismatch}
      end
    end
  end

  # The second complete pass is the envelope's anchor. Nothing after it can
  # quietly substitute browser-provider reads for trusted RPC evidence.
  def prepare(owner) do
    with :ok <- readiness(),
         {:ok, first} <- preflight(owner),
         true <- ready?(first),
         {:ok, final} <- preflight(owner),
         true <- ready?(final) do
      {:ok,
       %{
         anchor: final.block,
         owner: final.owner,
         base_uri: final.base_uri,
         token_uris: final.token_uris,
         total_supply: final.total_supply,
         erc4906_supported: final.erc4906_supported,
         owner_simulation: final.owner_simulation,
         non_owner_simulation: final.non_owner_simulation,
         runtime_keccak256: final.runtime_keccak256,
         gas_estimate: final.gas_estimate
       }}
    else
      false -> {:error, :contract_state_mismatch}
      {:error, reason} -> {:error, reason}
    end
  end

  def observe(envelope, hash) do
    with :ok <- observation_authorized(envelope),
         true <- valid_hash?(hash),
         :ok <- readiness(),
         {:ok, finalized} <- Rpc.finalized_block(@rpc_opts),
         {:ok, transaction} <- rpc("eth_getTransactionByHash", [hash]),
         {:ok, receipt} <- rpc("eth_getTransactionReceipt", [hash]),
         :ok <- ensure_observation_open(envelope) do
      transaction
      |> observe_pair(receipt, envelope, hash, finalized)
      |> normalize_observation_result()
    else
      false ->
        {:error, :invalid_observation}

      {:error, :observation_deadline_elapsed} ->
        {:ok, {:unknown, :observation_deadline_elapsed}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # A missing wallet hash never re-opens a send. Only a unique exact transaction
  # with the exact event inside this fixed post-anchor window can be recovered.
  def recover(envelope) do
    with :ok <- observation_authorized(envelope),
         :ok <- readiness(),
         {:ok, head} <- Rpc.safe_block(@rpc_opts),
         {:ok, hashes} <- scan(envelope, head),
         true <- Actions.observation_open?(envelope) do
      case hashes do
        [hash] -> observe(envelope, hash)
        [] -> {:ok, {:unknown, :no_unique_match}}
        _ -> {:ok, {:unknown, :multiple_matches}}
      end
    else
      false ->
        {:ok, {:unknown, :observation_deadline_elapsed}}

      {:error, :observation_deadline_elapsed} ->
        {:ok, {:unknown, :observation_deadline_elapsed}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp preflight(owner) do
    with {:ok, block} <- Rpc.safe_block(@rpc_opts),
         {:ok, state} <- snapshot(block),
         :ok <- simulate_owner(block, owner),
         :ok <- simulate_non_owner_revert(block),
         {:ok, gas} <- estimate_gas(block, owner) do
      {:ok,
       state
       |> Map.put(:block, block)
       |> Map.put(:owner_simulation, "success")
       |> Map.put(:non_owner_simulation, "revert")
       |> Map.put(:gas_estimate, gas)}
    end
  end

  defp snapshot(block) do
    with {:ok, code} <-
           rpc("eth_getCode", [RegentsClub.contract_address(), block_parameter(block)]),
         true <- code != "0x",
         true <- runtime_bytes(code) == RegentsClub.runtime_bytes(),
         {:ok, runtime_hash} <- verified_runtime_hash(code),
         {:ok, owner} <- read_address(RegentsClub.owner_calldata(), block),
         {:ok, base_uri} <- read_string(RegentsClub.base_uri_calldata(), block),
         {:ok, total_supply} <- read_uint(RegentsClub.total_supply_calldata(), block),
         {:ok, erc4906_supported} <- read_bool(RegentsClub.supports_erc4906_calldata(), block),
         {:ok, token_uris} <- boundary_uris(block) do
      {:ok,
       %{
         block: block,
         runtime_keccak256: runtime_hash,
         owner: owner,
         base_uri: base_uri,
         total_supply: total_supply,
         erc4906_supported: erc4906_supported,
         token_uris: token_uris
       }}
    else
      false -> {:error, :runtime_mismatch}
      :error -> {:error, :invalid_chain_response}
      {:error, reason} -> {:error, reason}
    end
  end

  defp boundary_uris(block) do
    with {:ok, first} <- read_string(RegentsClub.token_uri_calldata(1), block),
         {:ok, last} <- read_string(RegentsClub.token_uri_calldata(1998), block) do
      {:ok, %{first: first, last: last}}
    end
  end

  defp ready?(state),
    do:
      state.runtime_keccak256 == RegentsClub.runtime_keccak256() and
        state.owner == RegentsClub.owner() and state.base_uri == RegentsClub.old_base_uri() and
        state.total_supply == 1998 and state.erc4906_supported == true and
        state.token_uris == %{
          first: RegentsClub.old_base_uri() <> "1",
          last: RegentsClub.old_base_uri() <> "1998"
        }

  defp complete?(state),
    do:
      state.runtime_keccak256 == RegentsClub.runtime_keccak256() and
        state.owner == RegentsClub.owner() and state.base_uri == RegentsClub.new_base_uri() and
        state.total_supply == 1998 and state.erc4906_supported == true and
        state.token_uris == %{
          first: RegentsClub.new_base_uri() <> "1",
          last: RegentsClub.new_base_uri() <> "1998"
        }

  defp read_address(data, block) do
    with {:ok, result} <- call(data, block), do: RegentsClub.decode_address(result)
  end

  defp read_string(data, block) do
    with {:ok, result} <- call(data, block), do: RegentsClub.decode_string(result)
  end

  defp read_uint(data, block) do
    with {:ok, result} <- call(data, block), do: RegentsClub.decode_uint(result)
  end

  defp read_bool(data, block) do
    with {:ok, result} <- call(data, block), do: RegentsClub.decode_bool(result)
  end

  defp call(data, block),
    do:
      rpc("eth_call", [
        %{to: RegentsClub.contract_address(), data: data},
        block_parameter(block)
      ])

  defp simulate_owner(block, owner) do
    case rpc("eth_call", [transaction(owner), block_parameter(block)]) do
      {:ok, "0x"} -> :ok
      {:ok, _} -> {:error, :invalid_simulation_response}
      {:error, reason} -> {:error, reason}
    end
  end

  defp simulate_non_owner_revert(block) do
    case rpc_preserving_error("eth_call", [transaction(@non_owner), block_parameter(block)]) do
      {:rpc_error, error} when is_map(error) ->
        if expected_revert?(error), do: :ok, else: {:error, :invalid_non_owner_simulation}

      {:ok, _result} ->
        {:error, :non_owner_simulation_succeeded}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp estimate_gas(block, owner) do
    with {:ok, encoded} <- rpc("eth_estimateGas", [transaction(owner), block_parameter(block)]),
         {:ok, gas} <- quantity(encoded),
         true <- gas > 0 do
      {:ok, gas}
    else
      false -> {:error, :invalid_gas_estimate}
      :error -> {:error, :invalid_chain_response}
      {:error, reason} -> {:error, reason}
    end
  end

  defp transaction(owner),
    do: %{
      from: owner,
      to: RegentsClub.contract_address(),
      data: RegentsClub.calldata(),
      value: "0x0"
    }

  defp observe_pair(nil, nil, _envelope, _hash, _finalized), do: {:ok, :pending}
  defp observe_pair(_transaction, nil, _envelope, _hash, _finalized), do: {:ok, :pending}
  defp observe_pair(nil, _receipt, _envelope, _hash, _finalized), do: {:ok, :pending}

  defp observe_pair(transaction, receipt, envelope, hash, finalized) do
    with :ok <- transaction_identity(transaction, envelope, hash),
         :ok <- receipt_identity(receipt, hash),
         {:ok, number} <- quantity(receipt["blockNumber"]),
         true <- number <= finalized.number,
         :ok <- canonical(number, receipt["blockHash"]) do
      case receipt["status"] do
        "0x0" -> {:ok, :reverted}
        "0x1" -> verify_success(receipt, envelope, finalized)
        _ -> {:error, :invalid_receipt}
      end
    else
      false -> {:ok, :pending}
      :moved -> {:ok, :pending}
      :error -> {:error, :invalid_receipt}
      {:error, reason} -> {:error, reason}
    end
  end

  defp verify_success(%{"logs" => logs} = receipt, envelope, finalized) when is_list(logs) do
    with true <- RegentsClub.batch_metadata_event?(logs),
         :ok <- ensure_observation_open(envelope),
         {:ok, post_state} <- snapshot(finalized),
         :ok <- ensure_observation_open(envelope),
         true <- complete?(post_state) do
      {:ok,
       {:finalized,
        %{
          transaction_hash: String.downcase(receipt["transactionHash"]),
          block_number: quantity!(receipt["blockNumber"]),
          block_hash: String.downcase(receipt["blockHash"]),
          anchor_block_number: envelope.metadata.anchor_block_number,
          anchor_block_hash: envelope.metadata.anchor_block_hash,
          finality_block_number: finalized.number,
          finality_block_hash: finalized.hash,
          base_uri: post_state.base_uri,
          token_uris: post_state.token_uris
        }}}
    else
      false -> {:error, :post_state_mismatch}
      {:error, reason} -> {:error, reason}
    end
  end

  defp verify_success(_receipt, _envelope, _finalized), do: {:error, :invalid_receipt}

  defp scan(envelope, head) do
    first = envelope.metadata.anchor_block_number + 1
    last = min(head.number, envelope.metadata.anchor_block_number + @scan_blocks)

    if last < first do
      {:ok, []}
    else
      first..last
      |> Enum.reduce_while({:ok, []}, &collect_block_matches(&1, &2, envelope))
      |> scan_event_matches(envelope)
    end
  end

  defp collect_block_matches(number, {:ok, found}, envelope) do
    if Actions.observation_open?(envelope) do
      case matching_transactions(number, envelope) do
        {:ok, matches} -> {:cont, {:ok, found ++ matches}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    else
      {:halt, {:error, :observation_deadline_elapsed}}
    end
  end

  defp scan_event_matches({:ok, hashes}, envelope),
    do: hashes |> Enum.uniq() |> event_matches(envelope)

  defp scan_event_matches(error, _envelope), do: error

  defp matching_transactions(number, envelope) do
    with {:ok, %{"number" => encoded, "hash" => hash, "transactions" => transactions}}
         when is_list(transactions) <-
           rpc("eth_getBlockByNumber", [hex_quantity(number), true]),
         {:ok, ^number} <- quantity(encoded),
         true <- valid_hash?(hash) do
      {:ok,
       for(
         tx <- transactions,
         transaction_identity(tx, envelope, tx["hash"]) == :ok,
         do: tx["hash"]
       )}
    else
      false -> {:error, :invalid_block_header}
      {:ok, _malformed} -> {:error, :invalid_block_header}
      :error -> {:error, :invalid_block_header}
      {:error, reason} -> {:error, reason}
    end
  end

  defp event_matches(hashes, envelope) do
    hashes
    |> Enum.reduce_while({:ok, []}, &collect_event_match(&1, &2, envelope))
    |> reverse_event_matches()
  end

  defp collect_event_match(hash, {:ok, matches}, envelope) do
    if Actions.observation_open?(envelope),
      do: collect_open_event_match(hash, matches),
      else: {:halt, {:error, :observation_deadline_elapsed}}
  end

  defp collect_open_event_match(hash, matches) do
    case rpc("eth_getTransactionReceipt", [hash]) do
      {:ok, %{"status" => "0x1", "logs" => logs}} when is_list(logs) ->
        {:cont, {:ok, maybe_add_event_match(matches, hash, logs)}}

      {:ok, _not_successful} ->
        {:cont, {:ok, matches}}

      {:error, reason} ->
        {:halt, {:error, reason}}
    end
  end

  defp maybe_add_event_match(matches, hash, logs) do
    if RegentsClub.batch_metadata_event?(logs) do
      [hash | matches]
    else
      matches
    end
  end

  defp reverse_event_matches({:ok, matches}), do: {:ok, Enum.reverse(matches)}
  defp reverse_event_matches(error), do: error

  defp transaction_identity(tx, envelope, hash) when is_map(tx) do
    with true <- valid_hash?(hash),
         actual when is_binary(actual) <- tx["hash"],
         true <- String.downcase(actual) == String.downcase(hash),
         {:ok, from} <- Address.normalize(tx["from"]),
         true <- from == envelope.expected_signer,
         {:ok, to} <- Address.normalize(tx["to"]),
         true <- to == envelope.to,
         true <- String.downcase(tx["input"] || "") == envelope.data,
         true <- zero?(tx["value"]) do
      :ok
    else
      _ -> {:error, :transaction_mismatch}
    end
  end

  defp transaction_identity(_tx, _envelope, _hash), do: {:error, :transaction_missing}

  defp receipt_identity(%{"transactionHash" => actual}, expected) when is_binary(actual) do
    if String.downcase(actual) == String.downcase(expected),
      do: :ok,
      else: {:error, :receipt_mismatch}
  end

  defp receipt_identity(_receipt, _expected), do: {:error, :invalid_receipt}

  defp canonical(number, expected_hash) do
    with true <- valid_hash?(expected_hash),
         {:ok, %{"number" => encoded, "hash" => actual_hash}} <-
           rpc("eth_getBlockByNumber", [hex_quantity(number), false]),
         {:ok, ^number} <- quantity(encoded),
         true <-
           is_binary(actual_hash) and
             String.downcase(actual_hash) == String.downcase(expected_hash) do
      :ok
    else
      {:error, reason} -> {:error, reason}
      _ -> :moved
    end
  end

  defp block_parameter(%{hash: hash}), do: %{blockHash: hash, requireCanonical: true}
  defp rpc(method, params), do: Rpc.request(method, params, @rpc_opts)

  defp rpc_preserving_error(method, params),
    do: Rpc.request_preserving_rpc_error(method, params, @rpc_opts)

  defp expected_revert?(%{"code" => code} = error) when code in @revert_codes do
    message = Map.get(error, "message", "")
    data = Map.get(error, "data")

    (is_binary(message) and String.contains?(String.downcase(message), "revert")) or
      revert_data?(data)
  end

  defp expected_revert?(_error), do: false

  defp revert_data?("0x" <> hex),
    do:
      byte_size(hex) > 0 and rem(byte_size(hex), 2) == 0 and
        String.match?(hex, ~r/\A[0-9a-fA-F]+\z/)

  defp revert_data?(%{"data" => data}), do: revert_data?(data)
  defp revert_data?(_data), do: false

  defp runtime_bytes("0x" <> hex) when rem(byte_size(hex), 2) == 0, do: div(byte_size(hex), 2)
  defp runtime_bytes(_), do: -1

  if Mix.env() == :test do
    defp verified_runtime_hash(code) do
      case Application.get_env(:ash_platform, :regents_club_test_runtime_hasher) do
        hasher when is_function(hasher, 1) -> hasher.(code)
        _real_hash -> RegentsClub.runtime_hash(code)
      end
    end
  else
    defp verified_runtime_hash(code), do: RegentsClub.runtime_hash(code)
  end

  defp quantity("0x" <> hex) when hex != "" do
    case Integer.parse(hex, 16) do
      {number, ""} -> {:ok, number}
      _ -> :error
    end
  end

  defp quantity(_), do: :error
  defp quantity!(encoded), do: encoded |> quantity() |> elem(1)
  defp hex_quantity(number), do: "0x" <> Integer.to_string(number, 16)

  defp zero?("0x" <> hex) do
    case Integer.parse(hex, 16) do
      {0, ""} -> true
      _ -> false
    end
  end

  defp zero?(_), do: false

  defp valid_hash?("0x" <> hash),
    do: byte_size(hash) == 64 and String.match?(hash, ~r/\A[0-9a-fA-F]+\z/)

  defp valid_hash?(_), do: false

  defp observation_authorized(envelope) do
    if Actions.valid_observation_envelope?(envelope),
      do: ensure_observation_open(envelope),
      else: {:error, :invalid_observation}
  end

  defp ensure_observation_open(envelope) do
    if Actions.observation_open?(envelope),
      do: :ok,
      else: {:error, :observation_deadline_elapsed}
  end

  defp normalize_observation_result({:error, :observation_deadline_elapsed}),
    do: {:ok, {:unknown, :observation_deadline_elapsed}}

  defp normalize_observation_result(result), do: result
end
