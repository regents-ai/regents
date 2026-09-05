defmodule AshPlatform.BaseRpcStub do
  @moduledoc """
  One JSON-RPC transport double for the Base reads a Stake or Redeem test makes.

  Chain identity, the `latest` and `safe` headers, headers by number, receipts,
  transactions and recorded logs have exactly one shape for both surfaces. Only
  the block-pinned `eth_call` answers differ, so a test supplies those as the
  `:calls` function it installs.

  The two heads answer with different hashes, so a test that pins a read to one
  of them cannot silently pass against the other.
  """

  @safe_hash "0x" <> String.duplicate("5a", 32)
  @latest_hash "0x" <> String.duplicate("1c", 32)
  @receipt_block_hash "0x" <> String.duplicate("7b", 32)

  def safe_hash, do: @safe_hash
  def latest_hash, do: @latest_hash
  def receipt_block_hash, do: @receipt_block_hash

  def post(_url, options) do
    request = options[:json]
    state = state()
    if pid = state[:test_pid], do: send(pid, {:rpc, request.method, request.params})

    case result(request.method, request.params, state) do
      :unavailable -> {:ok, %{status: 200, body: %{"error" => %{"message" => "unavailable"}}}}
      result -> {:ok, %{status: 200, body: %{"result" => result}}}
    end
  end

  defmodule Timeout do
    @moduledoc "Refuses every request, so a transport failure is unavailable and never zero."
    def post(_url, _options), do: {:error, %Req.TransportError{reason: :timeout}}
  end

  defmodule UnsupportedCall do
    @moduledoc "Refuses only `eth_call`, so an unsupported block-pinned read fails closed."

    def post(url, options) do
      if options[:json].method == "eth_call",
        do: {:ok, %{status: 200, body: %{"error" => %{"message" => "unsupported"}}}},
        else: AshPlatform.BaseRpcStub.post(url, options)
    end
  end

  @doc "Points one wallet HTTP client at this stub for the duration of the test."
  def install(client_key, calls) do
    previous_http = Application.get_env(:ash_platform, client_key)
    previous_url = Application.get_env(:ash_platform, :base_read_rpc_url)
    Application.put_env(:ash_platform, client_key, __MODULE__)

    Application.put_env(
      :ash_platform,
      :base_read_rpc_url,
      "https://provider.invalid/super-secret"
    )

    put(%{test_pid: self(), calls: calls})

    ExUnit.Callbacks.on_exit(fn ->
      restore(client_key, previous_http)
      restore(:base_read_rpc_url, previous_url)
      Application.delete_env(:ash_platform, :rpc_stub)
    end)
  end

  @doc """
  Lets the aggregator's pinned identity be met by the code this stub returns.

  The deployed runtime is thousands of bytes no test can hold, so the hash the
  reader observes is supplied here while the length check still runs against
  the real pinned length.
  """
  def install_multicall3_identity do
    previous = Application.get_env(:ash_platform, :test_runtime_hasher)

    Application.put_env(
      :ash_platform,
      :test_runtime_hasher,
      fn _code -> AshPlatform.WalletActions.Abi.multicall3_runtime_keccak256() end
    )

    ExUnit.Callbacks.on_exit(fn -> restore(:test_runtime_hasher, previous) end)
  end

  def state, do: Application.get_env(:ash_platform, :rpc_stub, %{})

  def put(changes), do: Application.put_env(:ash_platform, :rpc_stub, Map.merge(state(), changes))

  @doc "A receipt with this status, mined into this block and carrying exactly these logs."
  def receipt(hash, block_number, logs, status \\ "0x1"),
    do: %{
      "status" => status,
      "blockNumber" => block_number,
      "blockHash" => @receipt_block_hash,
      "transactionHash" => hash,
      "logs" => logs
    }

  def transaction(hash, envelope),
    do: %{
      "hash" => hash,
      "from" => envelope.expected_signer,
      "to" => envelope.to,
      "input" => envelope.data,
      "value" => "0x0"
    }

  @doc "Every block a pinned `eth_call` was executed against, taken from this test's mailbox."
  def call_blocks(blocks \\ []) do
    receive do
      {:rpc, "eth_call", [_call, block]} -> call_blocks([block | blocks])
      {:rpc, _method, _params} -> call_blocks(blocks)
    after
      0 -> blocks
    end
  end

  @doc """
  One `aggregate3` response carrying exactly these `0x`-prefixed return values.

  Every entry reports success, because `allowFailure` is false on every
  sub-call a reader here makes and Multicall3 reverts rather than reporting one
  that did not.
  """
  def aggregate3_result(values) when is_list(values) do
    entries = Enum.map(values, &aggregate3_entry/1)
    heads_bytes = length(entries) * 32

    {heads, _next} =
      Enum.map_reduce(entries, heads_bytes, fn entry, offset ->
        {hex_word(offset), offset + div(byte_size(entry), 2)}
      end)

    "0x" <> hex_word(32) <> hex_word(length(entries)) <> Enum.join(heads) <> Enum.join(entries)
  end

  defp aggregate3_entry("0x" <> data),
    do:
      hex_word(1) <>
        hex_word(64) <>
        hex_word(div(byte_size(data), 2)) <>
        String.pad_trailing(data, div(byte_size(data) + 63, 64) * 64, "0")

  @doc "Deployed runtime code of exactly `bytes` length, for an identity check."
  def runtime_code(bytes), do: "0x" <> String.duplicate("ab", bytes)

  def uint(value), do: "0x" <> hex_word(value)

  def hex_word(value),
    do: value |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(64, "0")

  def address_word(address),
    do: address |> String.trim_leading("0x") |> String.downcase() |> String.pad_leading(64, "0")

  def address_topic(address), do: "0x" <> address_word(address)

  defp result("eth_chainId", _params, state), do: Map.get(state, :chain_id, "0x2105")

  defp result("eth_getBlockByNumber", ["safe", false], state),
    do: Map.get(state, :safe_block, %{"number" => "0x20", "hash" => @safe_hash})

  defp result("eth_getBlockByNumber", ["latest", false], state),
    do: Map.get(state, :latest_block, %{"number" => "0x20", "hash" => @latest_hash})

  defp result("eth_getBlockByNumber", [number, false], state),
    do:
      state
      |> Map.get(:blocks, %{})
      |> Map.get(number, %{"number" => number, "hash" => @receipt_block_hash})

  defp result("eth_getTransactionReceipt", [hash], state),
    do: state |> Map.get(:receipts, %{}) |> Map.get(hash)

  defp result("eth_getTransactionByHash", [hash], state),
    do: state |> Map.get(:transactions, %{}) |> Map.get(hash)

  defp result("eth_getCode", [_address, block], state) do
    if canonical?(block, state),
      do:
        Map.get_lazy(state, :code, fn ->
          runtime_code(AshPlatform.WalletActions.Abi.multicall3_runtime_bytes())
        end),
      else: :unavailable
  end

  defp result("eth_call", [%{data: data}, block], state) do
    if canonical?(block, state), do: state.calls.(data, state), else: :unavailable
  end

  # The logs this stub holds that the filter actually selects: this emitter,
  # these topics in these positions, and a block inside the requested range. A
  # reader asking for a range in pieces is answered piece by piece, so a piece
  # holding nothing answers with nothing rather than with the whole history.
  #
  # `:refused_log_range` names one `fromBlock`, so a test can fail exactly one
  # piece of a range and prove what a reader does with the rest.
  defp result("eth_getLogs", [filter], state) do
    if quantity(filter.fromBlock) == Map.get(state, :refused_log_range),
      do: :unavailable,
      else: state |> Map.get(:logs, []) |> Enum.filter(&selected?(&1, filter))
  end

  defp selected?(log, filter) do
    same_hex?(log["address"], filter.address) and
      matching_topics?(log["topics"], filter.topics) and
      quantity(log["blockNumber"]) in quantity(filter.fromBlock)..quantity(filter.toBlock)//1
  end

  defp same_hex?(left, right), do: String.downcase(left) == String.downcase(right)

  # A filter names the leading topics it wants and says nothing about the rest.
  defp matching_topics?(topics, wanted) do
    length(topics) >= length(wanted) and
      topics |> Enum.zip(wanted) |> Enum.all?(fn {topic, want} -> same_hex?(topic, want) end)
  end

  defp quantity("0x" <> hex), do: String.to_integer(hex, 16)

  # A block-pinned read is only answered when it names the canonical hash and
  # asks for canonicality, exactly as a Base node behaves. A test naming a
  # different canonical hash proves a moved block fails rather than answering,
  # and a read pinned any other way is never answered at all.
  defp canonical?(%{blockHash: hash, requireCanonical: true}, state),
    do: Map.get(state, :canonical_block_hash, hash) == hash

  defp canonical?(_block, _state), do: false

  defp restore(key, nil), do: Application.delete_env(:ash_platform, key)
  defp restore(key, value), do: Application.put_env(:ash_platform, key, value)
end
