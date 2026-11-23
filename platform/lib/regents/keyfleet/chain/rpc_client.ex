defmodule Regents.Keyfleet.Chain.RpcClient do
  @moduledoc """
  The chain reads the fleet reader and the wallet steps need, over JSON-RPC to
  the site's one Base read endpoint (`:base_read_rpc_url`, `Regents.Keyfleet.Chain.JsonRpc`).

  Logs come back exactly as `eth_getLogs` returns them; decoding them is
  `Regents.Keyfleet.Chain.Logs`'s job. Contract reads come back as the bytes the
  contract returned. One call asks for every contract and event the
  reader follows, so a stretch of blocks is always read whole.

  Every request the node does not answer, or answers with an error other than
  the contract refusing the call, is logged and counted in
  `health.chain_request_failures.total` (`RegentsWeb.Keyfleet.Telemetry`) under the
  scope "fleet", so Sentinel warns while the node keeps failing.
  """

  require Logger

  alias RegentChain.Abi
  alias Regents.Keyfleet.Chain.JsonRpc

  @type head :: %{
          number: non_neg_integer(),
          hash: String.t(),
          timestamp: DateTime.t(),
          base_fee: non_neg_integer()
        }

  @spec chain_id() :: {:ok, pos_integer()} | {:error, term()}
  def chain_id do
    with {:ok, result} <- request("eth_chainId", []) do
      case Abi.quantity(result) do
        {:ok, chain_id} -> {:ok, chain_id}
        :error -> {:error, :invalid_chain_id}
      end
    end
  end

  # Base makes five `latest` blocks a second from Denim; nothing here waits
  # for `safe` or `finalized`.
  @spec head() :: {:ok, head()} | {:error, term()}
  def head do
    with {:ok, header} <- block("latest"), do: head_of(header)
  end

  defp head_of(%{
         "number" => number,
         "hash" => hash,
         "timestamp" => timestamp,
         "baseFeePerGas" => base_fee
       }) do
    with {:ok, number} <- Abi.quantity(number),
         {:ok, seconds} <- Abi.quantity(timestamp),
         {:ok, timestamp} <- DateTime.from_unix(seconds),
         {:ok, base_fee} <- Abi.quantity(base_fee) do
      {:ok, %{number: number, hash: hash, timestamp: timestamp, base_fee: base_fee}}
    else
      _malformed -> {:error, :invalid_block_header}
    end
  end

  defp head_of(_header), do: {:error, :invalid_block_header}

  @spec get_logs(
          addresses :: [String.t()],
          topic0s :: [String.t()],
          from_block :: non_neg_integer(),
          to_block :: non_neg_integer()
        ) :: {:ok, [map()]} | {:error, term()}
  def get_logs(addresses, topic0s, from_block, to_block) do
    filter = %{
      address: addresses,
      topics: [topic0s],
      fromBlock: hex_quantity(from_block),
      toBlock: hex_quantity(to_block)
    }

    case request("eth_getLogs", [filter]) do
      {:ok, logs} when is_list(logs) -> {:ok, logs}
      {:ok, _other} -> {:error, :invalid_logs}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Calls a contract's view function with `data`, the `0x` calldata
  `RegentChain.Call.encode/2` builds, at the block whose hash is
  `block_hash`, and returns the bytes it returned. A call the contract refuses is
  `{:error, :reverted}`. A block that is no longer on the chain is an error,
  never another block's answer.
  """
  # EIP-1898: the node answers at exactly that block, and refuses once it is
  # no longer on the chain.
  @spec call(to :: String.t(), data :: String.t(), block_hash :: String.t()) ::
          {:ok, binary()} | {:error, term()}
  def call(to, data, block_hash) do
    case request("eth_call", [
           %{to: to, data: data},
           %{blockHash: block_hash, requireCanonical: true}
         ]) do
      {:ok, result} ->
        case Abi.bytes(result) do
          {:ok, bytes} -> {:ok, bytes}
          :error -> {:error, :invalid_call_result}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  The ETH `address` holds, in wei, at the block whose hash is `block_hash`. A
  block that is no longer on the chain is an error, never another block's
  answer.
  """
  @spec get_balance(address :: String.t(), block_hash :: String.t()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def get_balance(address, block_hash) do
    with {:ok, result} <-
           request("eth_getBalance", [address, %{blockHash: block_hash, requireCanonical: true}]) do
      case Abi.quantity(result) do
        {:ok, wei} -> {:ok, wei}
        :error -> {:error, :invalid_balance}
      end
    end
  end

  @doc """
  The code at `address`, as bytes, at the block whose hash is `block_hash`:
  empty for a plain wallet, the contract's code for a smart wallet, and the
  delegation for a wallet that delegates to one (EIP-7702).
  """
  @spec get_code(address :: String.t(), block_hash :: String.t()) ::
          {:ok, binary()} | {:error, term()}
  def get_code(address, block_hash) do
    with {:ok, result} <-
           request("eth_getCode", [address, %{blockHash: block_hash, requireCanonical: true}]) do
      case Abi.bytes(result) do
        {:ok, code} -> {:ok, code}
        :error -> {:error, :invalid_code}
      end
    end
  end

  defp block(tag) do
    case request("eth_getBlockByNumber", [tag, false]) do
      {:ok, %{"hash" => "0x" <> digits = hash} = header} when byte_size(digits) == 64 ->
        {:ok, %{header | "hash" => String.downcase(hash)}}

      {:ok, nil} ->
        {:error, :block_unavailable}

      {:ok, _header} ->
        {:error, :invalid_block_header}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # A node asking for fewer requests (HTTP 429) is `:chain_busy`, so a reader
  # asks it nothing more this pass; any other failure to answer is
  # `:chain_unavailable`.
  defp request(method, params) do
    case JsonRpc.request(method, params) do
      {:ok, result} ->
        {:ok, result}

      {:error, {:rpc_error, error}} ->
        refused_or_failed(method, error)

      {:error, {:unavailable, %{status: 429} = detail}} ->
        Logger.warning("chain read failed #{inspect(Map.put(detail, :method, method))}")
        count_failure(method, "http_429")
        {:error, :chain_busy}

      {:error, {:unavailable, detail}} ->
        Logger.warning("chain read failed #{inspect(Map.put(detail, :method, method))}")
        count_failure(method, class(detail))
        {:error, :chain_unavailable}
    end
  end

  # Nodes report a call the contract refused with error code 3, or with a
  # message that says so; anything else is the node failing.
  defp refused_or_failed(method, error) do
    if JsonRpc.reverted?(error) do
      {:error, :reverted}
    else
      Logger.warning(
        "chain read failed #{inspect(%{method: method, code: error.code, message: error.message})}"
      )

      count_failure(method, "rpc")
      {:error, :chain_unavailable}
    end
  end

  # The fleets live on the one wallet chain, which the node serves.
  defp count_failure(method, class) do
    [chain_id] = :regents |> Application.fetch_env!(:keyfleet_wallet_chains) |> Map.keys()

    :telemetry.execute([:regents, :chain, :failure], %{count: 1}, %{
      method: method,
      class: class,
      chain_id: chain_id,
      scope: "fleet"
    })
  end

  defp class(%{status: status}), do: "http_#{status}"

  defp class(%{reason: %Req.TransportError{reason: reason}})
       when reason in [:timeout, :connect_timeout],
       do: "timeout"

  defp class(%{reason: _transport}), do: "transport"

  defp hex_quantity(value), do: "0x" <> (value |> Integer.to_string(16) |> String.downcase())
end
