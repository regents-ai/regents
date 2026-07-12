defmodule AshPlatform.WalletActions.Rpc do
  @moduledoc false

  require Logger

  alias AshPlatform.WalletActions.Address

  @timeout 8_000
  @chain_id 8453

  def verify_base_chain(opts \\ []) do
    with {:ok, result} <- request("eth_chainId", [], opts),
         {chain_id, ""} <- parse_chain_id(result),
         true <- chain_id == @chain_id do
      :ok
    else
      {:error, reason} -> {:error, reason}
      false -> {:error, :wrong_chain}
      _ -> {:error, :invalid_chain_response}
    end
  end

  def confirmed_transaction(hash, signer, to, data, opts \\ []) do
    case submission_status(hash, signer, to, data, opts) do
      {:ok, :success} -> :ok
      {:ok, :reverted} -> {:error, :transaction_reverted}
      {:ok, :pending} -> {:error, :transaction_pending}
      {:error, reason} -> {:error, reason}
    end
  end

  def submission_status(hash, signer, to, data, opts \\ []) do
    with true <- valid_hash?(hash),
         :ok <- verify_base_chain(opts),
         {:ok, receipt} <- request("eth_getTransactionReceipt", [hash], opts),
         {:ok, transaction} <- request("eth_getTransactionByHash", [hash], opts),
         :ok <- verify_receipt_hash(receipt, hash),
         :ok <- verify_transaction(transaction, hash, signer, to, data) do
      case receipt do
        %{"status" => "0x1", "blockNumber" => block} when is_binary(block) -> {:ok, :success}
        %{"status" => "0x0", "blockNumber" => block} when is_binary(block) -> {:ok, :reverted}
        nil -> {:ok, :pending}
        _ -> {:error, :invalid_receipt}
      end
    else
      false -> {:error, :invalid_confirmation}
      {:error, reason} -> {:error, reason}
    end
  end

  def call_uint(to, data, opts \\ []), do: call(to, data, &decode_uint/1, opts)
  def call_bool(to, data, opts \\ []), do: call(to, data, &(decode_uint(&1) != 0), opts)
  def call_address(to, data, opts \\ []), do: call(to, data, &decode_address/1, opts)

  def call_words(to, data, count, opts \\ []) when is_integer(count) and count > 0 do
    call(to, data, &decode_words(&1, count), opts)
  end

  def request(method, params, opts \\ []) do
    request = %{jsonrpc: "2.0", id: 1, method: method, params: params}

    client =
      Application.get_env(
        :ash_platform,
        Keyword.get(opts, :client_key, :wallet_http_client),
        Req
      )

    case client.post(Application.fetch_env!(:ash_platform, :base_read_rpc_url),
           json: request,
           connect_options: [timeout: 3_000],
           pool_timeout: 3_000,
           receive_timeout: @timeout,
           retry: false
         ) do
      {:ok, %{status: 200, body: %{"result" => result}}} ->
        {:ok, result}

      {:ok, %{body: %{"error" => _error}}} ->
        {:error, :chain_unavailable}

      {:ok, _response} ->
        {:error, :chain_unavailable}

      {:error, reason} ->
        log_failure(method, reason, opts)
        {:error, :chain_unavailable}
    end
  rescue
    error ->
      log_failure(method, error, opts)
      {:error, :chain_unavailable}
  end

  def format_units(value, decimals) do
    value
    |> Decimal.new()
    |> Decimal.div(Decimal.new(Integer.pow(10, decimals)))
    |> Decimal.normalize()
    |> Decimal.to_string(:normal)
  end

  def valid_hash?("0x" <> hash),
    do: byte_size(hash) == 64 and String.match?(hash, ~r/^[0-9a-fA-F]+$/)

  def valid_hash?(_hash), do: false

  defp call(to, data, decoder, opts) do
    with {:ok, result} <- request("eth_call", [%{to: to, data: data}, "latest"], opts) do
      {:ok, decoder.(result)}
    end
  rescue
    _ -> {:error, :invalid_chain_response}
  end

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
         true <- String.downcase(transaction["input"] || "") == String.downcase(data),
         true <- zero_quantity?(transaction["value"]) do
      :ok
    else
      _ -> {:error, :transaction_mismatch}
    end
  end

  defp verify_transaction(_transaction, _hash, _signer, _to, _data),
    do: {:error, :transaction_missing}

  defp parse_chain_id("0x" <> hex) when hex != "", do: Integer.parse(hex, 16)
  defp parse_chain_id(_result), do: :error

  defp decode_uint("0x" <> hex), do: String.to_integer(hex, 16)

  defp decode_address("0x" <> hex) when byte_size(hex) == 64 do
    case Address.normalize("0x" <> String.slice(hex, -40, 40)) do
      {:ok, address} -> address
      :error -> raise ArgumentError, "invalid address"
    end
  end

  defp decode_words("0x" <> hex, count) when byte_size(hex) == count * 64 do
    for <<word::binary-size(64) <- hex>>, do: String.to_integer(word, 16)
  end

  defp zero_quantity?(value) when value in ["0x0", "0x", "0"], do: true
  defp zero_quantity?(_value), do: false

  defp log_failure(method, reason, opts) do
    scope = Keyword.get(opts, :log_scope, "wallet")

    Logger.warning(
      "#{scope} chain read failed #{inspect(%{method: method, class: error_class(reason)})}"
    )
  end

  defp error_class(%Req.TransportError{reason: reason})
       when reason in [:timeout, :connect_timeout],
       do: :timeout

  defp error_class(%Req.TransportError{}), do: :transport
  defp error_class(_reason), do: :transport
end
