defmodule AshPlatform.RegentsClub.RpcClient do
  @moduledoc false

  alias AshPlatform.RegentsClub
  alias AshPlatform.RegentsClub.Actions
  alias AshPlatform.WalletActions.{Address, Rpc}

  @rpc_opts [client_key: :regents_club_http_client, log_scope: "regents_club_metadata"]
  @scan_blocks 64

  def readiness, do: Rpc.verify_base_chain(@rpc_opts)

  def status do
    with :ok <- readiness(),
         {:ok, block} <- Rpc.safe_block(@rpc_opts),
         {:ok, state} <- snapshot(block) do
      cond do
        ready?(state) -> {:ok, Map.put(state, :state, :ready)}
        complete?(state) -> {:ok, Map.put(state, :state, :complete)}
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
         runtime_keccak256: final.runtime_keccak256,
         gas_estimate: final.gas_estimate
       }}
    else
      false -> {:error, :contract_state_mismatch}
      {:error, reason} -> {:error, reason}
    end
  end

  def observe(envelope, hash) do
    with true <- Actions.valid_observation_envelope?(envelope),
         true <- valid_hash?(hash),
         :ok <- readiness(),
         {:ok, safe} <- Rpc.safe_block(@rpc_opts),
         {:ok, transaction} <- rpc("eth_getTransactionByHash", [hash]),
         {:ok, receipt} <- rpc("eth_getTransactionReceipt", [hash]) do
      observe_pair(transaction, receipt, envelope, hash, safe)
    else
      false -> {:error, :invalid_observation}
      {:error, reason} -> {:error, reason}
    end
  end

  # A missing wallet hash never re-opens a send. Only a unique exact transaction
  # with the exact event inside this fixed post-anchor window can be recovered.
  def recover(envelope) do
    with true <- Actions.valid_observation_envelope?(envelope),
         :ok <- readiness(),
         {:ok, safe} <- Rpc.safe_block(@rpc_opts),
         {:ok, hashes} <- scan(envelope, safe) do
      case hashes do
        [hash] -> observe(envelope, hash)
        [] -> {:ok, {:unknown, :no_unique_match}}
        _ -> {:ok, {:unknown, :multiple_matches}}
      end
    else
      false -> {:error, :invalid_observation}
      {:error, reason} -> {:error, reason}
    end
  end

  defp preflight(owner) do
    with {:ok, block} <- Rpc.safe_block(@rpc_opts),
         {:ok, state} <- snapshot(block),
         :ok <- simulate(block, owner),
         {:ok, gas} <- estimate_gas(block, owner) do
      {:ok, state |> Map.put(:block, block) |> Map.put(:gas_estimate, gas)}
    end
  end

  defp snapshot(block) do
    with {:ok, code} <-
           rpc("eth_getCode", [RegentsClub.contract_address(), block_parameter(block)]),
         true <- code != "0x",
         {:ok, runtime_hash} <- RegentsClub.runtime_hash(code),
         {:ok, owner} <- read_address(RegentsClub.owner_calldata(), block),
         {:ok, base_uri} <- read_string(RegentsClub.base_uri_calldata(), block),
         {:ok, token_uris} <- boundary_uris(base_uri, block) do
      {:ok,
       %{
         block: block,
         runtime_keccak256: runtime_hash,
         owner: owner,
         base_uri: base_uri,
         token_uris: token_uris
       }}
    else
      false -> {:error, :runtime_mismatch}
      :error -> {:error, :invalid_chain_response}
      {:error, reason} -> {:error, reason}
    end
  end

  defp boundary_uris(base_uri, block) do
    if base_uri == RegentsClub.new_base_uri() do
      with {:ok, first} <- read_string(RegentsClub.token_uri_calldata(1), block),
           {:ok, last} <- read_string(RegentsClub.token_uri_calldata(1998), block) do
        {:ok, %{first: first, last: last}}
      end
    else
      {:ok, nil}
    end
  end

  defp ready?(state),
    do:
      state.runtime_keccak256 == RegentsClub.runtime_keccak256() and
        state.owner == RegentsClub.owner() and state.base_uri == RegentsClub.old_base_uri()

  defp complete?(state),
    do:
      state.runtime_keccak256 == RegentsClub.runtime_keccak256() and
        state.owner == RegentsClub.owner() and state.base_uri == RegentsClub.new_base_uri() and
        state.token_uris == %{
          first: RegentsClub.new_base_uri() <> "1",
          last: RegentsClub.new_base_uri() <> "1998"
        }

  defp read_address(data, block) do
    with {:ok, result} <- call(data, block),
         {:ok, value} <- RegentsClub.decode_address(result),
         do: {:ok, value}
  end

  defp read_string(data, block) do
    with {:ok, result} <- call(data, block),
         {:ok, value} <- RegentsClub.decode_string(result),
         do: {:ok, value}
  end

  defp call(data, block),
    do:
      rpc("eth_call", [
        %{to: RegentsClub.contract_address(), data: data},
        block_parameter(block)
      ])

  defp simulate(block, owner) do
    case rpc("eth_call", [transaction(owner), block_parameter(block)]) do
      {:ok, "0x"} -> :ok
      {:ok, _} -> {:error, :invalid_simulation_response}
      {:error, reason} -> {:error, reason}
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

  defp observe_pair(nil, nil, _envelope, _hash, _safe), do: {:ok, :pending}
  defp observe_pair(_transaction, nil, _envelope, _hash, _safe), do: {:ok, :pending}
  defp observe_pair(nil, _receipt, _envelope, _hash, _safe), do: {:ok, :pending}

  defp observe_pair(transaction, receipt, envelope, hash, safe) do
    with :ok <- transaction_identity(transaction, envelope, hash),
         :ok <- receipt_identity(receipt, hash),
         {:ok, number} <- quantity(receipt["blockNumber"]),
         true <- number <= safe.number,
         :ok <- canonical(number, receipt["blockHash"]) do
      case receipt["status"] do
        "0x0" -> {:ok, :reverted}
        "0x1" -> verify_success(receipt, envelope, safe)
        _ -> {:error, :invalid_receipt}
      end
    else
      false -> {:ok, :pending}
      :moved -> {:ok, :pending}
      :error -> {:error, :invalid_receipt}
      {:error, reason} -> {:error, reason}
    end
  end

  defp verify_success(%{"logs" => logs} = receipt, envelope, safe) when is_list(logs) do
    with true <- RegentsClub.batch_metadata_event?(logs),
         {:ok, post_state} <- snapshot(safe),
         true <- complete?(post_state) do
      {:ok,
       {:finalized,
        %{
          transaction_hash: String.downcase(receipt["transactionHash"]),
          block_number: quantity!(receipt["blockNumber"]),
          block_hash: String.downcase(receipt["blockHash"]),
          anchor_block_number: envelope.metadata.anchor_block_number,
          anchor_block_hash: envelope.metadata.anchor_block_hash,
          finality_block_number: safe.number,
          finality_block_hash: safe.hash,
          base_uri: post_state.base_uri,
          token_uris: post_state.token_uris
        }}}
    else
      false -> {:error, :post_state_mismatch}
      {:error, reason} -> {:error, reason}
    end
  end

  defp verify_success(_receipt, _envelope, _safe), do: {:error, :invalid_receipt}

  defp scan(envelope, safe) do
    first = envelope.metadata.anchor_block_number + 1
    last = min(safe.number, envelope.metadata.anchor_block_number + @scan_blocks)

    if last < first do
      {:ok, []}
    else
      Enum.reduce_while(first..last, {:ok, []}, fn number, {:ok, found} ->
        case rpc("eth_getBlockByNumber", [hex_quantity(number), true]) do
          {:ok, %{"transactions" => transactions}} when is_list(transactions) ->
            matches =
              for tx <- transactions,
                  transaction_identity(tx, envelope, tx["hash"]) == :ok,
                  exact_event?(tx["hash"]),
                  do: tx["hash"]

            {:cont, {:ok, found ++ matches}}

          {:ok, _} ->
            {:halt, {:error, :invalid_block_header}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end)
      |> case do
        {:ok, hashes} -> {:ok, Enum.uniq(hashes)}
        error -> error
      end
    end
  end

  defp exact_event?(hash) do
    case rpc("eth_getTransactionReceipt", [hash]) do
      {:ok, %{"status" => "0x1", "logs" => logs}} -> RegentsClub.batch_metadata_event?(logs)
      _ -> false
    end
  end

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
         {:ok, %{"hash" => actual_hash}} <-
           rpc("eth_getBlockByNumber", [hex_quantity(number), false]),
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
end
