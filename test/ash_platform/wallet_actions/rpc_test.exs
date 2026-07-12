defmodule AshPlatform.WalletActions.RpcTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias AshPlatform.WalletActions.Rpc

  @hash "0x" <> String.duplicate("ab", 32)
  @signer "0x1111111111111111111111111111111111111111"
  @target "0x2222222222222222222222222222222222222222"
  @data "0xabcdef"

  defmodule Client do
    def post(_url, options) do
      send(self(), {:wallet_http_client, options[:json]})
      {:ok, %{status: 200, body: %{"result" => "0x2105"}}}
    end
  end

  defmodule FailingClient do
    def post(_url, _options), do: {:error, :offline}
  end

  defmodule SequenceClient do
    def post(_url, _options) do
      [reply | rest] = Process.get(:rpc_replies)
      Process.put(:rpc_replies, rest)
      {:ok, %{status: 200, body: %{"result" => reply}}}
    end
  end

  defmodule RoutedClient do
    def post(_url, options) do
      method = options[:json][:method]
      result = Process.get({:rpc_result, method})
      {:ok, %{status: 200, body: %{"result" => result}}}
    end
  end

  setup do
    previous = Application.get_env(:ash_platform, :wallet_http_client)
    Application.put_env(:ash_platform, :wallet_http_client, Client)
    on_exit(fn -> restore(:wallet_http_client, previous) end)
  end

  test "uses the generic wallet client by default" do
    assert :ok = Rpc.verify_base_chain()
    assert_received {:wallet_http_client, %{method: "eth_chainId"}}
  end

  test "uses the generic wallet log scope by default" do
    Application.put_env(:ash_platform, :wallet_http_client, FailingClient)

    log =
      capture_log(fn -> assert {:error, :chain_unavailable} = Rpc.request("eth_chainId", []) end)

    assert log =~ "wallet chain read failed"
    refute log =~ "staking chain read failed"
  end

  test "requires successfully normalized signer and target before equality" do
    valid = transaction()
    zero = "0x" <> String.duplicate("0", 40)

    assert_status(:success, valid, @signer, @target, @data)
    mixed_case_signer = "0x" <> String.upcase(String.trim_leading(@signer, "0x"))
    assert_status(:success, %{valid | "from" => mixed_case_signer}, @signer, @target, @data)

    for {case_name, transaction, signer, target} <- [
          {:invalid_actual_signer, %{valid | "from" => "bad"}, @signer, @target},
          {:invalid_expected_signer, valid, "bad", @target},
          {:both_signers_invalid, %{valid | "from" => "bad"}, "also-bad", @target},
          {:zero_signers, %{valid | "from" => zero}, zero, @target},
          {:wrong_signer, %{valid | "from" => @target}, @signer, @target},
          {:wrong_target, %{valid | "to" => @signer}, @signer, @target},
          {:both_targets_invalid, %{valid | "to" => "bad"}, @signer, "also-bad"}
        ] do
      assert_error(case_name, :transaction_mismatch, transaction, signer, target, @data)
    end
  end

  test "rejects hash, calldata and value drift" do
    valid = transaction()

    assert_error(
      :wrong_hash,
      :transaction_mismatch,
      %{valid | "hash" => "0x" <> String.duplicate("cd", 32)},
      @signer,
      @target,
      @data
    )

    assert_error(
      :wrong_calldata,
      :transaction_mismatch,
      %{valid | "input" => "0xdead"},
      @signer,
      @target,
      @data
    )

    assert_error(
      :nonzero_value,
      :transaction_mismatch,
      %{valid | "value" => "0x1"},
      @signer,
      @target,
      @data
    )
  end

  test "distinguishes successful, reverted, pending, mismatched and invalid receipts" do
    assert_status(:success, transaction(), @signer, @target, @data)
    assert_status(:reverted, transaction(), @signer, @target, @data, "0x0")

    Process.put(:rpc_replies, ["0x2105", nil, transaction()])
    Application.put_env(:ash_platform, :wallet_http_client, SequenceClient)
    assert {:ok, :pending} = Rpc.submission_status(@hash, @signer, @target, @data)

    assert_receipt_error(
      %{
        "status" => "0x1",
        "blockNumber" => "0x1",
        "transactionHash" => "0x" <> String.duplicate("cd", 32)
      },
      :receipt_mismatch
    )

    assert_receipt_error(
      %{"status" => "0x2", "blockNumber" => "0x1", "transactionHash" => @hash},
      :invalid_receipt
    )
  end

  test "rejects a successful receipt when the injected provider is not Base" do
    receipt = %{"status" => "0x1", "blockNumber" => "0x1", "transactionHash" => @hash}

    for chain_result <- ["0x1", "not-hex", nil] do
      Process.put({:rpc_result, "eth_chainId"}, chain_result)
      Process.put({:rpc_result, "eth_getTransactionReceipt"}, receipt)
      Process.put({:rpc_result, "eth_getTransactionByHash"}, transaction())
      Application.put_env(:ash_platform, :wallet_http_client, RoutedClient)
      refute match?({:ok, :success}, Rpc.submission_status(@hash, @signer, @target, @data))
    end
  end

  defp transaction do
    %{"hash" => @hash, "from" => @signer, "to" => @target, "input" => @data, "value" => "0x0"}
  end

  defp assert_status(status, transaction, signer, target, data, receipt_status \\ "0x1") do
    receipt = %{"status" => receipt_status, "blockNumber" => "0x1", "transactionHash" => @hash}
    Process.put(:rpc_replies, ["0x2105", receipt, transaction])
    Application.put_env(:ash_platform, :wallet_http_client, SequenceClient)
    assert {:ok, ^status} = Rpc.submission_status(@hash, signer, target, data)
  end

  defp assert_error(case_name, reason, transaction, signer, target, data) do
    receipt = %{"status" => "0x1", "blockNumber" => "0x1", "transactionHash" => @hash}
    Process.put(:rpc_replies, ["0x2105", receipt, transaction])
    Application.put_env(:ash_platform, :wallet_http_client, SequenceClient)
    result = Rpc.submission_status(@hash, signer, target, data)
    assert result == {:error, reason}, "#{case_name} unexpectedly returned #{inspect(result)}"
  end

  defp assert_receipt_error(receipt, reason) do
    Process.put(:rpc_replies, ["0x2105", receipt, transaction()])
    Application.put_env(:ash_platform, :wallet_http_client, SequenceClient)
    assert {:error, ^reason} = Rpc.submission_status(@hash, @signer, @target, @data)
  end

  defp restore(key, nil), do: Application.delete_env(:ash_platform, key)
  defp restore(key, value), do: Application.put_env(:ash_platform, key, value)
end
