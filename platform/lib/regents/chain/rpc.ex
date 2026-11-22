defmodule Regents.Chain.Rpc do
  @moduledoc false

  require Logger

  alias RegentChain.BuilderCode
  alias Regents.Chain.{Abi, Address}

  @timeout 8_000
  @chain_id 8453
  @environment to_string(Mix.env())

  @type block :: %{number: non_neg_integer(), hash: String.t(), timestamp: non_neg_integer()}

  @typedoc "The block a `call_*` read is pinned to: its hash, whatever else the map holds."
  @type pinned :: %{required(:hash) => String.t(), optional(atom()) => term()}

  def verify_base_chain(opts \\ []) do
    with {:ok, result} <- request("eth_chainId", [], opts),
         {:ok, chain_id} <- quantity(result),
         true <- chain_id == @chain_id do
      :ok
    else
      {:error, reason} -> {:error, reason}
      false -> {:error, :wrong_chain}
      _ -> {:error, :invalid_chain_response}
    end
  end

  @doc """
  One `latest` Base block, accepted only after the chain identity is proved.

  Base's sequencer confirms `latest` first, so this is the head a person waiting
  on their own transaction is actually watching. Every read pinned
  to it uses this block hash, so a page never mixes two histories and a moved
  block fails rather than answering.
  """
  @spec latest_block(keyword()) :: {:ok, block()} | {:error, atom()}
  def latest_block(opts \\ []) do
    with :ok <- verify_base_chain(opts),
         {:ok, header} <- request("eth_getBlockByNumber", ["latest", false], opts),
         do: block_identity(header)
  end

  @doc """
  One `safe` Base block, accepted only after the chain identity is proved.

  Every read of a snapshot is then executed against this exact block hash, so a
  page never mixes two histories and a moved block fails rather than answering.
  """
  @spec safe_block(keyword()) :: {:ok, block()} | {:error, atom()}
  def safe_block(opts \\ []) do
    with :ok <- verify_base_chain(opts),
         {:ok, header} <- request("eth_getBlockByNumber", ["safe", false], opts),
         do: block_identity(header)
  end

  @doc "When a block was made, in whole seconds, as the block itself says."
  @spec block_timestamp(non_neg_integer(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, atom()}
  def block_timestamp(number, opts \\ []) do
    with {:ok, header} <- request("eth_getBlockByNumber", [hex_quantity(number), false], opts),
         {:ok, block} <- block_identity(header),
         do: {:ok, block.timestamp}
  end

  @doc """
  Whether `block` is still part of its chain: the block now at its number is
  the same one. Newer blocks on top of it leave it so.
  """
  @spec canonical?(
          %{required(:number) => non_neg_integer(), required(:hash) => String.t()},
          keyword()
        ) :: {:ok, boolean()} | {:error, atom()}
  def canonical?(%{number: number, hash: hash}, opts \\ []) do
    with {:ok, header} <- request("eth_getBlockByNumber", [hex_quantity(number), false], opts),
         {:ok, now} <- block_identity(header),
         do: {:ok, now.hash == hash}
  end

  @doc """
  The exact canonical outcome of one submitted transaction against one safe head.

  `:pending` is every state that may still resolve differently: a hash this RPC
  has not observed yet, no receipt yet, a receipt above the safe head, and a
  receipt whose block is no longer canonical. Success and revert are both read
  only from a receipt that is already canonical, so neither can be reported from
  a block this transaction may yet leave.

  The safe block passed in already proved the chain identity, so nothing here
  asks for it a second time.
  """
  @spec canonical_outcome(String.t(), String.t(), String.t(), String.t(), block(), keyword()) ::
          {:ok, :pending | :reverted | {:success, [map()]}} | {:error, atom()}
  def canonical_outcome(hash, signer, to, data, safe_block, opts \\ []) do
    with {:ok, receipt} <- identified_receipt(hash, signer, to, data, opts),
         {:ok, number, block_hash} <- receipt_block(receipt),
         :ok <- canonical(number, block_hash, safe_block, opts) do
      settled(receipt)
    end
  end

  defp identified_receipt(hash, signer, to, data, opts) do
    with true <- valid_hash?(hash),
         {:ok, receipt} <- request("eth_getTransactionReceipt", [hash], opts),
         {:ok, transaction} <- request("eth_getTransactionByHash", [hash], opts),
         :ok <- verify_receipt_hash(receipt, hash),
         :ok <- observed_identity(receipt, transaction, hash, signer, to, data) do
      {:ok, receipt}
    else
      false -> {:error, :invalid_confirmation}
      {:error, reason} -> {:error, reason}
    end
  end

  # A hash the wallet has just broadcast may not have reached this read RPC yet.
  # With neither a receipt nor the transaction itself, nothing has been observed
  # about it: the same hash stays pending rather than becoming unverifiable.
  defp observed_identity(nil, nil, _hash, _signer, _to, _data), do: :ok

  defp observed_identity(_receipt, transaction, hash, signer, to, data),
    do: verify_transaction(transaction, hash, signer, to, data)

  defp verify_receipt_hash(nil, _hash), do: :ok

  defp verify_receipt_hash(%{"transactionHash" => receipt_hash}, hash)
       when is_binary(receipt_hash) do
    if String.downcase(receipt_hash) == String.downcase(hash),
      do: :ok,
      else: {:error, :receipt_mismatch}
  end

  defp verify_receipt_hash(_receipt, _hash), do: {:error, :invalid_receipt}

  defp verify_transaction(transaction, hash, signer, to, data) when is_map(transaction) do
    with {:ok, actual_signer} <- Address.normalize(transaction["from"]),
         {:ok, expected_signer} <- Address.normalize(signer),
         {:ok, actual_target} <- Address.normalize(transaction["to"]),
         {:ok, expected_target} <- Address.normalize(to),
         transaction_hash when is_binary(transaction_hash) <- transaction["hash"],
         true <- String.downcase(transaction_hash) == String.downcase(hash),
         true <- actual_signer == expected_signer,
         true <- actual_target == expected_target,
         {:ok, sent} <- sent_call(transaction["input"]),
         {:ok, reviewed} <- sent_call(data),
         true <- sent == reviewed,
         true <- zero_quantity?(transaction["value"]) do
      :ok
    else
      _ -> {:error, :transaction_mismatch}
    end
  end

  defp verify_transaction(_transaction, _hash, _signer, _to, _data),
    do: {:error, :transaction_missing}

  # The calldata without any Builder Code suffix, which a wallet may rewrite.
  defp sent_call("0x" <> _hex = data), do: {:ok, data |> String.downcase() |> BuilderCode.call()}
  defp sent_call(_input), do: :error

  defp zero_quantity?(value) when value in ["0x0", "0x", "0"], do: true
  defp zero_quantity?(_value), do: false

  # `{:ok, :pending}` here is the whole answer: the `with` above carries it out
  # unchanged rather than reading a status this receipt does not have yet.
  defp receipt_block(nil), do: {:ok, :pending}

  defp receipt_block(%{"blockNumber" => number, "blockHash" => hash, "logs" => logs})
       when is_list(logs) do
    with {:ok, number} <- quantity(number),
         true <- valid_hash?(hash) do
      {:ok, number, String.downcase(hash)}
    else
      _malformed -> {:error, :invalid_receipt}
    end
  end

  defp receipt_block(_receipt), do: {:error, :invalid_receipt}

  # Above the safe head, and mined into a block that is no longer the canonical
  # one, are both states this transaction may still leave: neither is an answer,
  # whichever status the receipt carries right now.
  defp canonical(number, _hash, %{number: safe}, _opts) when number > safe, do: {:ok, :pending}

  defp canonical(number, hash, _safe, opts) do
    with {:ok, header} <- request("eth_getBlockByNumber", [hex_quantity(number), false], opts),
         {:ok, %{hash: ^hash}} <- block_identity(header) do
      :ok
    else
      {:error, reason} -> {:error, reason}
      _moved -> {:ok, :pending}
    end
  end

  defp settled(%{"status" => "0x1", "logs" => logs}), do: {:ok, {:success, logs}}
  defp settled(%{"status" => "0x0"}), do: {:ok, :reverted}
  defp settled(_receipt), do: {:error, :invalid_receipt}

  @doc """
  One answer read as a number: any `0x` quantity, whatever its length.

  Each `call_*` read is one `eth_call` pinned to `block`'s hash with
  `requireCanonical`. A revert, a moved block or no answer gives
  `{:error, :chain_unavailable}`; an answer that does not decode gives
  `{:error, :invalid_chain_response}`.
  """
  @spec call_uint(String.t(), String.t(), pinned(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, atom()}
  def call_uint(to, data, block, opts \\ []), do: call(to, data, block, &quantity/1, opts)

  @doc "One answer read as a number, true when it is not zero."
  @spec call_bool(String.t(), String.t(), pinned(), keyword()) ::
          {:ok, boolean()} | {:error, atom()}
  def call_bool(to, data, block, opts \\ []) do
    call(
      to,
      data,
      block,
      fn result -> with {:ok, word} <- quantity(result), do: {:ok, word != 0} end,
      opts
    )
  end

  @doc """
  One word read as the address in its last twenty bytes, the bytes above them
  unread. The zero address is not an answer.
  """
  @spec call_address(String.t(), String.t(), pinned(), keyword()) ::
          {:ok, String.t()} | {:error, atom()}
  def call_address(to, data, block, opts \\ []), do: call(to, data, block, &word_address/1, opts)

  @doc "An answer of exactly `count` words, each read as a number."
  @spec call_words(String.t(), String.t(), pinned(), pos_integer(), keyword()) ::
          {:ok, [non_neg_integer()]} | {:error, atom()}
  def call_words(to, data, block, count, opts \\ []) when is_integer(count) and count > 0 do
    call(to, data, block, &quantities(&1, count), opts)
  end

  @doc "One ABI string answer, such as an ERC-20 `name()` or `symbol()`."
  @spec call_string(String.t(), String.t(), pinned(), keyword()) ::
          {:ok, String.t()} | {:error, atom()}
  def call_string(to, data, block, opts \\ []), do: call(to, data, block, &abi_string/1, opts)

  @doc """
  One ABI string answer as the bytes the contract holds, which need not be
  valid UTF-8: text someone else wrote, such as a launch's token name.
  """
  @spec call_bytes(String.t(), String.t(), pinned(), keyword()) ::
          {:ok, binary()} | {:error, atom()}
  def call_bytes(to, data, block, opts \\ []), do: call(to, data, block, &abi_bytes/1, opts)

  @doc "One answer as the bytes the contract returned, left undecoded."
  @spec call_raw(String.t(), String.t(), pinned(), keyword()) ::
          {:ok, binary()} | {:error, atom()}
  def call_raw(to, data, block, opts \\ []), do: call(to, data, block, &raw_bytes/1, opts)

  # EIP-1898: the block hash owns the read and `requireCanonical` refuses an
  # answer from a block that is no longer part of the chain.
  defp call(to, data, %{hash: hash}, decode, opts) do
    with {:ok, result} <-
           request(
             "eth_call",
             [%{to: to, data: data}, %{blockHash: hash, requireCanonical: true}],
             opts
           ) do
      case decode.(result) do
        {:ok, value} -> {:ok, value}
        :error -> {:error, :invalid_chain_response}
      end
    end
  end

  @doc """
  An `address` read that tells a contract's refusal apart from a read that did
  not happen: `{:reverted, data}` carries the revert data the contract answered
  with, and every other failure is an `{:error, reason}`.
  """
  def call_address_or_revert(to, data, %{hash: hash}, opts \\ []) do
    params = [%{to: to, data: data}, %{blockHash: hash, requireCanonical: true}]

    case post("eth_call", params, opts) do
      {:ok, %{status: 200, body: %{"error" => %{"data" => "0x" <> _ = revert}}}} ->
        {:reverted, revert}

      response ->
        with {:ok, result} <- result(response, "eth_call", opts),
             {:ok, address} <- decode_address(result) do
          {:ok, address}
        else
          :error -> {:error, :invalid_chain_response}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @doc """
  Several reads of one Base block, answered by one `eth_call` to `aggregator`.

  `calls` is the ordered list of `{target, calldata, kind}` this read wants,
  `kind` being `:uint`, `:bool`, `:address`, `:addresses` for a call returning
  one `address[]`, or `{:words, count}` for a call returning exactly `count`
  unsigned words. The whole aggregate is pinned to
  the caller's block hash with `requireCanonical`, exactly as a single read is,
  so a moved block fails rather than answering, and `allowFailure` is `false`,
  so a reverting sub-call reverts everything and the page is told the chain is
  unavailable instead of being handed a partial reading.
  """
  @type kind :: :uint | :bool | :address | :addresses | {:words, pos_integer()}

  @spec aggregate3(String.t(), [{String.t(), String.t(), kind()}], block(), keyword()) ::
          {:ok, [term()]} | {:error, atom()}
  def aggregate3(aggregator, calls, %{hash: hash}, opts \\ []) when calls != [] do
    data = Abi.encode_aggregate3(Enum.map(calls, fn {to, calldata, _kind} -> {to, calldata} end))

    with {:ok, result} <-
           request(
             "eth_call",
             [
               %{to: aggregator, data: data},
               %{blockHash: hash, requireCanonical: true}
             ],
             opts
           ),
         {:ok, returned} <- Abi.decode_aggregate3(result, length(calls)),
         {:ok, decoded} <- decode_each(returned, calls) do
      {:ok, decoded}
    else
      :error -> {:error, :invalid_chain_response}
      {:error, reason} -> {:error, reason}
    end
  rescue
    _ -> {:error, :invalid_chain_response}
  end

  @doc """
  The runtime code deployed at `address`, proved against a pinned identity.

  The check runs against the same block hash the reads themselves are pinned
  to, so the code that answered a read and the code that was identified are the
  same code, and a `requireCanonical` refusal fails the whole reading.
  """
  @spec verified_runtime_code(String.t(), String.t(), non_neg_integer(), block(), keyword()) ::
          :ok | {:error, atom()}
  def verified_runtime_code(address, keccak256, bytes, %{hash: hash}, opts \\ []) do
    with {:ok, "0x" <> hex} <-
           request("eth_getCode", [address, %{blockHash: hash, requireCanonical: true}], opts),
         {:ok, code} <- Base.decode16(hex, case: :mixed),
         true <- byte_size(code) == bytes,
         true <- keccak256(code) == keccak256 do
      :ok
    else
      {:error, reason} -> {:error, reason}
      _mismatch -> {:error, :runtime_mismatch}
    end
  end

  defp keccak256(bytes),
    do: "0x" <> Base.encode16(:jose_jwa_sha3.keccak(1088, 512, bytes, 1, 32), case: :lower)

  defp decode_each(returned, calls) do
    returned
    |> Enum.zip(calls)
    |> Enum.reduce_while({:ok, []}, fn {value, {_to, _data, kind}}, {:ok, decoded} ->
      case decode_kind(kind, value) do
        {:ok, decoded_value} -> {:cont, {:ok, [decoded_value | decoded]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, decoded} -> {:ok, Enum.reverse(decoded)}
      :error -> :error
    end
  end

  defp decode_kind(:uint, value), do: decode_uint(value)
  defp decode_kind(:bool, value), do: decode_bool(value)
  defp decode_kind(:address, value), do: decode_address(value)
  defp decode_kind(:addresses, value), do: decode_addresses(value)
  defp decode_kind({:words, count}, value), do: decode_words(value, count)

  @doc """
  Every log `address` emitted with `topics` from block `from` to block `to`. A
  span the node refuses, as too many blocks or too many logs, is read again as
  its two halves, down to one block; a node that does not answer fails the read
  at once.
  """
  @spec logs(String.t(), list(), non_neg_integer(), non_neg_integer(), keyword()) ::
          {:ok, [map()]} | {:error, atom()}
  def logs(address, topics, from, to, opts) do
    filter = %{
      address: address,
      topics: topics,
      fromBlock: hex_quantity(from),
      toBlock: hex_quantity(to)
    }

    case answer("eth_getLogs", [filter], opts) do
      {:ok, logs} when is_list(logs) -> {:ok, logs}
      {:ok, _other} -> {:error, :invalid_chain_response}
      {:error, {:rpc, _error}} when from < to -> halves(address, topics, from, to, opts)
      {:error, _reason} -> {:error, :chain_unavailable}
    end
  end

  defp halves(address, topics, from, to, opts) do
    middle = div(from + to, 2)

    with {:ok, low} <- logs(address, topics, from, middle, opts),
         {:ok, high} <- logs(address, topics, middle + 1, to, opts),
         do: {:ok, low ++ high}
  end

  @doc """
  The first block at or below `head` where `address` holds code, found by
  halving the chain with `eth_getCode`: about log2(head) one-block requests,
  never a log range a provider can refuse for its width.
  """
  @spec deployment_block(String.t(), non_neg_integer(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, :history_unavailable}
  def deployment_block(address, head, opts), do: code_since(address, 0, head, opts)

  defp code_since(_address, same, same, _opts), do: {:ok, same}

  defp code_since(address, low, high, opts) do
    middle = div(low + high, 2)

    case request("eth_getCode", [address, hex_quantity(middle)], opts) do
      {:ok, "0x"} -> code_since(address, middle + 1, high, opts)
      {:ok, "0x" <> code} when byte_size(code) > 0 -> code_since(address, low, middle, opts)
      _ -> {:error, :history_unavailable}
    end
  end

  def request(method, params, opts \\ []) do
    case answer(method, params, opts) do
      {:error, {:rpc, _error}} -> {:error, :chain_unavailable}
      answer -> answer
    end
  end

  # As `request/3`, but a node that answers with a JSON-RPC error gives
  # `{:error, {:rpc, error}}`, the answer's `error` object, apart from no answer.
  def answer(method, params, opts \\ []),
    do: method |> post(params, opts) |> result(method, opts)

  defp post(method, params, opts) do
    # Base unless the caller names another chain's endpoint.
    url =
      Keyword.get_lazy(opts, :url, fn -> Application.fetch_env!(:regents, :base_read_rpc_url) end)

    if purpose = Keyword.get(opts, :purpose) do
      :telemetry.execute([:regents, :staking, :rpc], %{requests: 1}, %{
        purpose: purpose,
        method: method,
        chain_id: @chain_id,
        environment: @environment
      })
    end

    Req.post(url,
      json: %{jsonrpc: "2.0", id: 1, method: method, params: params},
      finch: [pool_timeout: 3_000, conn_opts: [transport_opts: [timeout: 3_000]]],
      receive_timeout: @timeout,
      retry: &provider_busy/2,
      max_retries: 1
    )
  rescue
    error -> {:error, error}
  end

  # A provider that answers 429 is asked once more after the pause it names,
  # held to two seconds so a page never waits long on it; Req logs the retry.
  defp provider_busy(_request, %Req.Response{status: 429} = response),
    do: {:delay, min(retry_after(response), 2_000)}

  defp provider_busy(_request, _response_or_exception), do: false

  # A Retry-After that is neither whole seconds nor an HTTP date, or that comes
  # twice, is ignored as HTTP asks, and the second ask waits one second.
  defp retry_after(response) do
    Req.Response.get_retry_after(response) || 1_000
  rescue
    _malformed in [ArgumentError, CaseClauseError] -> 1_000
  end

  defp result({:ok, %{status: 200, body: %{"result" => result}}}, _method, _opts),
    do: {:ok, result}

  defp result({:ok, %{status: 200, body: %{"error" => %{} = error}}}, method, opts) do
    failed(method, "rpc", opts)
    {:error, {:rpc, error}}
  end

  defp result({:ok, %{status: status}}, method, opts) do
    failed(method, "http_#{status}", opts)

    Logger.warning(
      "#{scope(opts)} chain read refused #{inspect(%{method: method, status: status})}"
    )

    {:error, :chain_unavailable}
  end

  defp result({:error, reason}, method, opts) do
    failed(method, error_class(reason), opts)

    Logger.warning(
      "#{scope(opts)} chain read failed #{inspect(%{method: method, class: error_class(reason)})}"
    )

    {:error, :chain_unavailable}
  end

  # Every request that got no answer counts in `health.chain_request_failures.total`,
  # under the caller's fixed `scope` and the chain it asked.
  defp failed(method, class, opts) do
    :telemetry.execute([:regents, :chain, :failure], %{count: 1}, %{
      method: method,
      class: class,
      chain_id: Keyword.get(opts, :chain_id, @chain_id),
      scope: scope(opts)
    })
  end

  defp scope(opts), do: Keyword.get(opts, :scope, "wallet")

  def format_units(value, decimals) do
    value
    |> Decimal.new()
    |> Decimal.div(Decimal.new(Integer.pow(10, decimals)))
    |> Decimal.normalize()
    |> Decimal.to_string(:normal)
  end

  # `\z` and not `$`: `$` also matches before a trailing newline, which let
  # "0x" <> 63 hex <> "\n" pass the 64-byte guard as a canonical hash.
  def valid_hash?("0x" <> hash),
    do: byte_size(hash) == 64 and String.match?(hash, ~r/^[0-9a-fA-F]+\z/)

  def valid_hash?(_hash), do: false

  defp block_identity(%{"number" => number, "hash" => hash, "timestamp" => timestamp}) do
    with {:ok, number} <- quantity(number),
         true <- valid_hash?(hash),
         {:ok, timestamp} <- quantity(timestamp) do
      {:ok, %{number: number, hash: String.downcase(hash), timestamp: timestamp}}
    else
      _malformed -> {:error, :invalid_block_header}
    end
  end

  defp block_identity(_header), do: {:error, :invalid_block_header}

  defp quantity("0x" <> hex) when hex != "" do
    case Integer.parse(hex, 16) do
      {value, ""} -> {:ok, value}
      _malformed -> :error
    end
  end

  defp quantity(_value), do: :error

  defp hex_quantity(value), do: "0x" <> (value |> Integer.to_string(16) |> String.downcase())

  defp decode_uint(value) do
    with {:ok, hex} <- exact_hex(value, 64), do: parse_hex(hex)
  end

  defp decode_bool(value) do
    with {:ok, value} <- decode_uint(value),
         true <- value in [0, 1] do
      {:ok, value == 1}
    else
      _ -> :error
    end
  end

  defp decode_address(value) do
    with {:ok, hex} <- exact_hex(value, 64),
         true <- String.match?(String.slice(hex, 0, 24), ~r/^0+\z/),
         {:ok, address} <- Address.normalize("0x" <> String.slice(hex, -40, 40)) do
      {:ok, address}
    else
      _ -> :error
    end
  end

  defp decode_words(value, count) do
    case exact_hex(value, count * 64) do
      {:ok, hex} -> {:ok, for(<<word::binary-size(64) <- hex>>, do: String.to_integer(word, 16))}
      :error -> :error
    end
  end

  # One `address[]` and nothing after it: the offset to the list, its length,
  # then exactly that many address words.
  defp decode_addresses("0x" <> hex = value)
       when byte_size(hex) >= 128 and rem(byte_size(hex), 64) == 0 do
    count = div(byte_size(hex), 64) - 2

    with {:ok, [32, ^count | _]} <- decode_words(value, count + 2),
         addresses =
           for(<<word::binary-size(64) <- binary_part(hex, 128, count * 64)>>,
             do: decode_address("0x" <> word)
           ),
         false <- :error in addresses do
      {:ok, Enum.map(addresses, fn {:ok, address} -> address end)}
    else
      _ -> :error
    end
  end

  defp decode_addresses(_value), do: :error

  defp exact_hex("0x" <> hex, size) when byte_size(hex) == size do
    if String.match?(hex, ~r/\A[0-9a-fA-F]+\z/), do: {:ok, hex}, else: :error
  end

  defp exact_hex(_value, _size), do: :error

  defp parse_hex(hex) do
    case Integer.parse(hex, 16) do
      {value, ""} -> {:ok, value}
      _ -> :error
    end
  end

  # The `call_*` decoders, which are not `decode_uint/1` and its kin on purpose:
  # those read one entry of `aggregate3/4`'s encoded tuple and take nothing but
  # an exact word, while these read the raw answer of one `eth_call` as
  # Autolaunch's callers always have. A number is any `quantity/1`, whatever its
  # length; an address is a word's last twenty bytes; a bool is any number but
  # zero. Tightening one changes an answer about money, so each stays until a
  # matched proof shows no real answer needs it.
  defp word_address("0x" <> hex) when byte_size(hex) == 64,
    do: Address.normalize("0x" <> String.slice(hex, -40, 40))

  defp word_address(_result), do: :error

  defp quantities("0x" <> hex, count) when byte_size(hex) == count * 64 do
    words = for <<word::binary-size(64) <- hex>>, do: quantity("0x" <> word)
    if :error in words, do: :error, else: {:ok, Enum.map(words, fn {:ok, word} -> word end)}
  end

  defp quantities(_result, _count), do: :error

  # An ABI string is its offset word, its length word and its bytes.
  defp abi_string(result) do
    with {:ok, bytes} <- abi_bytes(result),
         true <- String.valid?(bytes) do
      {:ok, bytes}
    else
      _malformed -> :error
    end
  end

  defp abi_bytes("0x" <> hex) when byte_size(hex) >= 128 do
    with {:ok, [_offset, length]} <- quantities("0x" <> binary_part(hex, 0, 128), 2),
         true <- (128 + length * 2) in 0..byte_size(hex) do
      Base.decode16(binary_part(hex, 128, length * 2), case: :mixed)
    else
      _malformed -> :error
    end
  end

  defp abi_bytes(_result), do: :error

  defp raw_bytes("0x" <> hex), do: Base.decode16(hex, case: :mixed)
  defp raw_bytes(_result), do: :error

  defp error_class(%Req.TransportError{reason: reason})
       when reason in [:timeout, :connect_timeout],
       do: "timeout"

  defp error_class(_transport), do: "transport"
end
