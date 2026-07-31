defmodule AshPlatform.Autolaunch.BuybackRpcClientTest do
  use ExUnit.Case, async: false

  alias AshPlatform.Autolaunch.BuybackRpcClient
  alias AshPlatform.WalletActions.{BuybackAbi, Envelope}

  @wallet "0x1111111111111111111111111111111111111111"
  @router "0x2222222222222222222222222222222222222222"
  @treasury "0x3333333333333333333333333333333333333333"
  @subject_id "0x" <> String.duplicate("42", 32)
  @hash "0x" <> String.duplicate("ab", 32)

  defmodule HttpStub do
    def post(url, opts) do
      send(self(), {:http_post, url, opts[:json].method})
      request = opts[:json]

      {:ok,
       %{
         status: 200,
         body: %{"jsonrpc" => "2.0", "id" => 1, "result" => result(request)}
       }}
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
    previous_http = Application.get_env(:ash_platform, :autolaunch_buyback_http_client)
    previous_url = Application.get_env(:ash_platform, :base_read_rpc_url)
    previous_clock = Application.get_env(:ash_platform, :wallet_action_clock)

    Application.put_env(:ash_platform, :autolaunch_buyback_http_client, HttpStub)
    Application.put_env(:ash_platform, :base_read_rpc_url, "https://chain.invalid/buyback-test")
    Application.put_env(:ash_platform, :wallet_action_clock, fn -> ~U[2026-07-31 12:00:00Z] end)

    on_exit(fn ->
      restore(:autolaunch_buyback_http_client, previous_http)
      restore(:base_read_rpc_url, previous_url)
      restore(:wallet_action_clock, previous_clock)
      Process.delete(:receipts)
      Process.delete(:transactions)
    end)

    :ok
  end

  test "matches signer, router, zero value and calldata exactly" do
    envelope = envelope()
    put_success(@hash, @wallet, @router, envelope.data)

    assert {:ok, %{transaction_hash: @hash, receipt_verified: true}} =
             BuybackRpcClient.confirm(envelope, @hash)

    assert_received {:http_post, "https://chain.invalid/buyback-test", "eth_chainId"}

    for field <- ["from", "to", "input", "value"] do
      original = Process.get(:transactions)

      changed =
        case field do
          "from" -> @treasury
          "to" -> @treasury
          "input" -> "0xdeadbeef"
          "value" -> "0x1"
        end

      Process.put(:transactions, put_in(original[@hash][field], changed))
      assert {:error, :transaction_mismatch} = BuybackRpcClient.confirm(envelope, @hash)
      Process.put(:transactions, original)
    end
  end

  test "distinguishes reverted and pending receipts" do
    envelope = envelope()
    put_success(@hash, @wallet, @router, envelope.data)
    Process.put(:receipts, put_in(Process.get(:receipts)[@hash]["status"], "0x0"))

    assert {:error, :transaction_reverted} = BuybackRpcClient.confirm(envelope, @hash)

    Process.put(:receipts, %{@hash => nil})
    assert {:error, :transaction_pending} = BuybackRpcClient.confirm(envelope, @hash)
  end

  test "uses only the buyback client key and a reserved invalid endpoint" do
    source = File.read!("test/ash_platform/autolaunch/buyback_rpc_client_test.exs")
    assert source =~ ":autolaunch_buyback_http_client"
    assert source =~ "chain.invalid"
  end

  defp envelope do
    data = BuybackAbi.encode_settlement(@subject_id, @treasury, 11_000_000, 10 ** 19, @subject_id)

    Envelope.new("settle_treasury_buyback", @wallet, data,
      to: @router,
      resource: "autolaunch_buyback",
      contract_name: "RegentStakingRevenueRouter",
      risk_copy: "Settle this buyback.",
      arguments: %{
        subject_id: @subject_id,
        treasury: @treasury,
        amount_usdc_atomic: "11000000",
        minimum_regent_output_atomic: "10000000000000000000"
      }
    )
  end

  defp put_success(hash, from, to, input) do
    Process.put(:receipts, %{
      hash => %{
        "status" => "0x1",
        "blockNumber" => "0x10",
        "transactionHash" => hash
      }
    })

    Process.put(:transactions, %{
      hash => %{
        "hash" => hash,
        "from" => from,
        "to" => to,
        "input" => input,
        "value" => "0x0"
      }
    })
  end

  defp restore(key, nil), do: Application.delete_env(:ash_platform, key)
  defp restore(key, value), do: Application.put_env(:ash_platform, key, value)
end
