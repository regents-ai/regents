defmodule AshPlatform.Staking.RpcClientTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias AshPlatform.Staking.RpcClient
  alias AshPlatform.WalletActions.{Abi, Envelope}

  @wallet "0x1111111111111111111111111111111111111111"
  @tx_hash "0x" <> String.duplicate("ab", 32)

  defmodule HttpStub do
    def post(_url, opts) do
      request = opts[:json]
      {:ok, %{status: 200, body: %{"jsonrpc" => "2.0", "id" => 1, "result" => result(request)}}}
    end

    defp result(%{method: "eth_chainId"}), do: "0x2105"

    defp result(%{method: "eth_getTransactionReceipt", params: [hash]}) do
      Process.get(:receipts, %{}) |> Map.get(hash, Process.get(:receipt))
    end

    defp result(%{method: "eth_getTransactionByHash", params: [hash]}) do
      Process.get(:transactions, %{}) |> Map.get(hash, Process.get(:transaction))
    end

    defp result(%{method: "eth_call", params: [%{data: data} | _]}) do
      cond do
        data == Abi.encode_read("stake_token") -> word_address(Abi.stake_token_address())
        data == Abi.encode_read("usdc") -> word_address(Abi.usdc_address())
        true -> word_uint(5)
      end
    end

    defp word_uint(value), do: "0x" <> String.pad_leading(Integer.to_string(value, 16), 64, "0")

    defp word_address(address) do
      "0x" <> (address |> String.trim_leading("0x") |> String.pad_leading(64, "0"))
    end
  end

  defmodule TimeoutStub do
    def post(_url, _opts), do: {:error, %Req.TransportError{reason: :timeout}}
  end

  setup do
    previous_http = Application.get_env(:ash_platform, :staking_http_client)
    previous_url = Application.get_env(:ash_platform, :base_read_rpc_url)
    Application.put_env(:ash_platform, :staking_http_client, HttpStub)

    Application.put_env(
      :ash_platform,
      :base_read_rpc_url,
      "https://provider.invalid/super-secret"
    )

    on_exit(fn ->
      restore(:staking_http_client, previous_http)
      restore(:base_read_rpc_url, previous_url)
      Process.delete(:receipt)
      Process.delete(:transaction)
      Process.delete(:receipts)
      Process.delete(:transactions)
    end)

    :ok
  end

  test "account overview reads both REGENT and USDC wallet balances" do
    assert {:ok, snapshot} = RpcClient.overview(@wallet)

    assert snapshot.wallet_address == @wallet
    assert snapshot.wallet_token_balance == "0.000000000000000005"
    assert snapshot.wallet_usdc_balance == "0.000005"
  end

  test "stake confirmation requires an exact successful approval transaction" do
    approval_hash = "0x" <> String.duplicate("cd", 32)
    amount = 1_500_000_000_000_000_000
    approval_data = Abi.encode_erc20("approve", [Abi.staking_address(), amount])

    envelope =
      Envelope.new("stake", @wallet, Abi.encode_action("stake", [amount, @wallet]),
        risk_copy: "Stake REGENT.",
        arguments: %{amount_atomic: Integer.to_string(amount), receiver: @wallet},
        approval: %{
          token: Abi.stake_token_address(),
          spender: Abi.staking_address(),
          amount: Integer.to_string(amount),
          data: approval_data,
          mode: "exact"
        }
      )

    Process.put(:receipts, %{
      approval_hash => %{
        "status" => "0x1",
        "blockNumber" => "0x10",
        "transactionHash" => approval_hash
      },
      @tx_hash => %{
        "status" => "0x1",
        "blockNumber" => "0x11",
        "transactionHash" => @tx_hash
      }
    })

    exact_approval = %{
      "hash" => approval_hash,
      "from" => @wallet,
      "to" => Abi.stake_token_address(),
      "input" => approval_data,
      "value" => "0x0"
    }

    Process.put(:transactions, %{
      approval_hash => exact_approval,
      @tx_hash => %{
        "hash" => @tx_hash,
        "from" => @wallet,
        "to" => Abi.staking_address(),
        "input" => envelope.data,
        "value" => "0x0"
      }
    })

    assert {:error, :approval_required} = RpcClient.confirm(envelope, @tx_hash, nil)

    assert {:ok, %{receipt_verified: true}} =
             RpcClient.confirm(envelope, @tx_hash, approval_hash)

    Process.put(:transactions, %{
      approval_hash => %{exact_approval | "input" => "0xdeadbeef"},
      @tx_hash => Process.get(:transactions)[@tx_hash]
    })

    assert {:error, :transaction_mismatch} =
             RpcClient.confirm(envelope, @tx_hash, approval_hash)

    Process.put(:receipts, %{
      approval_hash => %{
        "status" => "0x0",
        "blockNumber" => "0x10",
        "transactionHash" => approval_hash
      }
    })

    assert {:error, :transaction_mismatch} =
             RpcClient.confirm(envelope, @tx_hash, approval_hash)

    Process.put(:transactions, %{
      approval_hash => exact_approval,
      @tx_hash => Process.get(:transactions)[@tx_hash]
    })

    assert {:error, :transaction_reverted} =
             RpcClient.confirm(envelope, @tx_hash, approval_hash)
  end

  test "confirmation requires a successful receipt and exact signer, target, value and calldata" do
    envelope =
      Envelope.new("claim_usdc", @wallet, Abi.encode_action("claim_usdc", [@wallet]),
        risk_copy: "Claim USDC.",
        arguments: %{recipient: @wallet}
      )

    Process.put(:receipt, %{
      "status" => "0x1",
      "blockNumber" => "0x10",
      "transactionHash" => @tx_hash
    })

    Process.put(:transaction, %{
      "hash" => @tx_hash,
      "from" => @wallet,
      "to" => Abi.staking_address(),
      "input" => envelope.data,
      "value" => "0x0"
    })

    assert {:ok, %{transaction_hash: @tx_hash, staking: %{wallet_address: @wallet}}} =
             RpcClient.confirm(envelope, @tx_hash, nil)

    Process.put(:receipt, %{
      "status" => "0x0",
      "blockNumber" => "0x10",
      "transactionHash" => @tx_hash
    })

    assert {:error, :transaction_reverted} = RpcClient.confirm(envelope, @tx_hash, nil)

    Process.put(:receipt, %{
      "status" => "0x0",
      "transactionHash" => @tx_hash
    })

    assert {:error, :invalid_receipt} = RpcClient.confirm(envelope, @tx_hash, nil)

    Process.put(:receipt, %{
      "status" => "0x1",
      "blockNumber" => "0x10",
      "transactionHash" => @tx_hash
    })

    Process.put(:transaction, %{
      "hash" => @tx_hash,
      "from" => @wallet,
      "to" => Abi.staking_address(),
      "input" => "0xdeadbeef",
      "value" => "0x0"
    })

    assert {:error, :transaction_mismatch} = RpcClient.confirm(envelope, @tx_hash, nil)

    Process.put(:transaction, %{
      "hash" => @tx_hash,
      "from" => "0x2222222222222222222222222222222222222222",
      "to" => Abi.staking_address(),
      "input" => envelope.data,
      "value" => "0x0"
    })

    assert {:error, :transaction_mismatch} = RpcClient.confirm(envelope, @tx_hash, nil)

    Process.put(:receipt, %{
      "status" => "0x1",
      "blockNumber" => "0x10",
      "transactionHash" => "0x" <> String.duplicate("cd", 32)
    })

    assert {:error, :receipt_mismatch} = RpcClient.confirm(envelope, @tx_hash, nil)

    Process.put(:receipt, nil)

    Process.put(:transaction, %{
      "hash" => @tx_hash,
      "from" => @wallet,
      "to" => Abi.staking_address(),
      "input" => envelope.data,
      "value" => "0x0"
    })

    assert {:error, :transaction_pending} = RpcClient.confirm(envelope, @tx_hash, nil)

    Process.put(:transaction, %{
      "hash" => "0x" <> String.duplicate("ef", 32),
      "from" => @wallet,
      "to" => Abi.staking_address(),
      "input" => envelope.data,
      "value" => "0x0"
    })

    assert {:error, :transaction_mismatch} = RpcClient.confirm(envelope, @tx_hash, nil)

    Process.put(:transaction, nil)
    assert {:error, :transaction_missing} = RpcClient.confirm(envelope, @tx_hash, nil)

    Process.put(:transaction, %{
      "from" => @wallet,
      "to" => Abi.staking_address(),
      "input" => envelope.data,
      "value" => "0x0"
    })

    assert {:error, :transaction_mismatch} = RpcClient.confirm(envelope, @tx_hash, nil)
  end

  test "transport logs never reveal the provider URL" do
    Application.put_env(:ash_platform, :staking_http_client, TimeoutStub)

    log = capture_log(fn -> assert {:error, :chain_unavailable} = RpcClient.overview(nil) end)

    assert log =~ "class: :timeout"
    refute log =~ "super-secret"
    refute log =~ "provider.invalid"
  end

  defp restore(key, nil), do: Application.delete_env(:ash_platform, key)
  defp restore(key, value), do: Application.put_env(:ash_platform, key, value)
end
