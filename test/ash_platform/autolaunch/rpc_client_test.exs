defmodule AshPlatform.Autolaunch.RpcClientTest do
  use ExUnit.Case, async: false

  alias AshPlatform.Autolaunch.RpcClient
  alias AshPlatform.WalletActions.{AuctionAbi, Envelope}

  @wallet "0x1111111111111111111111111111111111111111"
  @auction "0x2222222222222222222222222222222222222222"
  @token "0x3333333333333333333333333333333333333333"
  @hash "0x" <> String.duplicate("ab", 32)
  @approval_hash "0x" <> String.duplicate("cd", 32)

  defmodule HttpStub do
    def post(url, opts) do
      send(self(), {:http_post, url, opts[:json].method})
      request = opts[:json]
      {:ok, %{status: 200, body: %{"jsonrpc" => "2.0", "id" => 1, "result" => result(request)}}}
    end

    defp result(%{method: "eth_chainId"}), do: "0x2105"

    defp result(%{method: "eth_getTransactionReceipt", params: [hash]}) do
      Process.get(:receipts, %{}) |> Map.get(hash)
    end

    defp result(%{method: "eth_getTransactionByHash", params: [hash]}) do
      Process.get(:transactions, %{}) |> Map.get(hash)
    end
  end

  setup do
    previous_http = Application.get_env(:ash_platform, :autolaunch_bid_http_client)
    previous_url = Application.get_env(:ash_platform, :base_read_rpc_url)
    previous_clock = Application.get_env(:ash_platform, :wallet_action_clock)

    Application.put_env(:ash_platform, :autolaunch_bid_http_client, HttpStub)
    Application.put_env(:ash_platform, :base_read_rpc_url, "https://provider.invalid/test-only")
    Application.put_env(:ash_platform, :wallet_action_clock, fn -> ~U[2026-07-31 12:00:00Z] end)

    on_exit(fn ->
      restore(:autolaunch_bid_http_client, previous_http)
      restore(:base_read_rpc_url, previous_url)
      restore(:wallet_action_clock, previous_clock)
      Process.delete(:receipts)
      Process.delete(:transactions)
    end)

    :ok
  end

  test "matches approval and bid receipt fields exactly" do
    envelope = bid_envelope()
    put_success(@approval_hash, @wallet, @token, envelope.approval.data)
    put_success(@hash, @wallet, @auction, envelope.data)

    assert {:ok, %{transaction_hash: @hash, receipt_verified: true}} =
             RpcClient.confirm(envelope, @hash, @approval_hash)

    assert_received {:http_post, "https://provider.invalid/test-only", "eth_chainId"}

    Process.put(
      :transactions,
      put_in(Process.get(:transactions)[@hash]["from"], @token)
    )

    assert {:error, :transaction_mismatch} =
             RpcClient.confirm(envelope, @hash, @approval_hash)
  end

  test "reports missing approval, reverted action and pending action" do
    envelope = bid_envelope()
    put_success(@approval_hash, @wallet, @token, envelope.approval.data)
    put_success(@hash, @wallet, @auction, envelope.data)

    assert {:error, :approval_required} = RpcClient.confirm(envelope, @hash, nil)

    Process.put(
      :receipts,
      put_in(Process.get(:receipts)[@hash]["status"], "0x0")
    )

    assert {:error, :transaction_reverted} =
             RpcClient.confirm(envelope, @hash, @approval_hash)

    Process.put(:receipts, Map.put(Process.get(:receipts), @hash, nil))

    assert {:error, :transaction_pending} =
             RpcClient.confirm(envelope, @hash, @approval_hash)
  end

  # A hash the wallet has just broadcast may not have reached this read RPC at
  # all. Neither read observed it, so nothing is known about it: this client
  # keeps reporting pending and never success or a permanent failure.
  test "a transaction neither read has observed stays pending" do
    envelope = bid_envelope()
    put_success(@approval_hash, @wallet, @token, envelope.approval.data)

    assert {:error, :transaction_pending} =
             RpcClient.confirm(envelope, @hash, @approval_hash)

    Process.put(:receipts, %{})
    Process.put(:transactions, %{})

    assert {:ok, :pending} = RpcClient.approval_status(envelope, @approval_hash)
  end

  test "approval status distinguishes success, reverted and pending" do
    envelope = bid_envelope()
    put_success(@approval_hash, @wallet, @token, envelope.approval.data)

    assert {:ok, :success} = RpcClient.approval_status(envelope, @approval_hash)

    Process.put(
      :receipts,
      put_in(Process.get(:receipts)[@approval_hash]["status"], "0x0")
    )

    assert {:ok, :reverted} = RpcClient.approval_status(envelope, @approval_hash)

    Process.put(:receipts, %{@approval_hash => nil})
    assert {:ok, :pending} = RpcClient.approval_status(envelope, @approval_hash)
  end

  test "tests configure only the injectable client and invalid reserved endpoint" do
    source = File.read!("test/ash_platform/autolaunch/rpc_client_test.exs")
    assert source =~ ":autolaunch_bid_http_client"
    assert source =~ "provider.invalid"

    assert Regex.scan(
             ~r/Application\.put_env\(:ash_platform, :base_read_rpc_url, "([^"]+)"\)/,
             source,
             capture: :all_but_first
           ) == [["https://provider.invalid/test-only"]]
  end

  defp bid_envelope do
    amount = 12_500_000

    data =
      AuctionAbi.encode_submit_bid(3 * 79_228_162_514_264_337_593_543_950_336, amount, @wallet)

    Envelope.new("submit_bid", @wallet, data,
      to: @auction,
      resource: "autolaunch_auction",
      contract_name: "IContinuousClearingAuction",
      risk_copy: "Submit this bid.",
      approval: %{
        token: @token,
        spender: @auction,
        amount: Integer.to_string(amount),
        data: AuctionAbi.encode_approval(@auction, amount),
        mode: "exact"
      },
      arguments: %{auction_id: Ash.UUID.generate()}
    )
  end

  defp put_success(hash, from, to, input) do
    receipts =
      Map.put(Process.get(:receipts, %{}), hash, %{
        "status" => "0x1",
        "blockNumber" => "0x10",
        "transactionHash" => hash
      })

    transactions =
      Map.put(Process.get(:transactions, %{}), hash, %{
        "hash" => hash,
        "from" => from,
        "to" => to,
        "input" => input,
        "value" => "0x0"
      })

    Process.put(:receipts, receipts)
    Process.put(:transactions, transactions)
  end

  defp restore(key, nil), do: Application.delete_env(:ash_platform, key)
  defp restore(key, value), do: Application.put_env(:ash_platform, key, value)
end
