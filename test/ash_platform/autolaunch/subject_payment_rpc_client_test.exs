defmodule AshPlatform.Autolaunch.SubjectPaymentRpcClientTest do
  use ExUnit.Case, async: false

  alias AshPlatform.Autolaunch.SubjectPaymentRpcClient
  alias AshPlatform.WalletActions.{Envelope, SubjectPaymentAbi}

  @wallet "0x1111111111111111111111111111111111111111"
  @token "0x2222222222222222222222222222222222222222"
  @splitter "0x3333333333333333333333333333333333333333"
  @factory "0x4444444444444444444444444444444444444444"
  @receiver "0x5555555555555555555555555555555555555555"
  @subject_id "0x" <> String.duplicate("53", 32)
  @hash "0x" <> String.duplicate("ab", 32)
  @approval_hash "0x" <> String.duplicate("cd", 32)

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

    defp result(%{method: "eth_chainId"}), do: Process.get(:chain_id, "0x2105")

    defp result(%{method: "eth_getTransactionReceipt", params: [hash]}) do
      Process.get(:receipts, %{}) |> Map.get(hash)
    end

    defp result(%{method: "eth_getTransactionByHash", params: [hash]}) do
      Process.get(:transactions, %{}) |> Map.get(hash)
    end
  end

  setup do
    previous_http =
      Application.get_env(:ash_platform, :autolaunch_subject_payment_http_client)

    previous_url = Application.get_env(:ash_platform, :base_read_rpc_url)
    previous_clock = Application.get_env(:ash_platform, :wallet_action_clock)

    Application.put_env(:ash_platform, :autolaunch_subject_payment_http_client, HttpStub)

    Application.put_env(
      :ash_platform,
      :base_read_rpc_url,
      "https://chain.invalid/subject-payment-test"
    )

    Application.put_env(:ash_platform, :wallet_action_clock, fn -> ~U[2026-07-31 12:00:00Z] end)

    on_exit(fn ->
      restore(:autolaunch_subject_payment_http_client, previous_http)
      restore(:base_read_rpc_url, previous_url)
      restore(:wallet_action_clock, previous_clock)
      Process.delete(:chain_id)
      Process.delete(:receipts)
      Process.delete(:transactions)
    end)

    :ok
  end

  test "matches signer, stored target, zero value and calldata exactly" do
    envelope = payment_link_envelope()

    put_success(@hash, @wallet, @factory, envelope.data, [
      payment_link_created_log(@factory, @subject_id, @receiver)
    ])

    assert {:ok,
            %{
              transaction_hash: @hash,
              receipt_verified: true,
              payment_link_receiver: @receiver
            }} =
             SubjectPaymentRpcClient.confirm(envelope, @hash, nil)

    assert_received {:http_post, "https://chain.invalid/subject-payment-test", "eth_chainId"}

    for {field, changed} <- [
          {"from", @splitter},
          {"to", @splitter},
          {"input", "0xdeadbeef"},
          {"value", "0x1"}
        ] do
      original = Process.get(:transactions)
      Process.put(:transactions, put_in(original[@hash][field], changed))

      assert {:error, :transaction_mismatch} =
               SubjectPaymentRpcClient.confirm(envelope, @hash, nil)

      Process.put(:transactions, original)
    end
  end

  test "requires and receipt-matches the exact stake approval" do
    envelope = stake_envelope()
    put_success(@approval_hash, @wallet, @token, envelope.approval.data)
    put_success(@hash, @wallet, @splitter, envelope.data)

    assert {:ok, %{receipt_verified: true}} =
             SubjectPaymentRpcClient.confirm(envelope, @hash, @approval_hash)

    assert {:ok, :success} =
             SubjectPaymentRpcClient.approval_status(envelope, @approval_hash)

    assert {:error, :approval_required} =
             SubjectPaymentRpcClient.confirm(envelope, @hash, nil)

    transactions = Process.get(:transactions)
    Process.put(:transactions, put_in(transactions[@approval_hash]["input"], "0xdeadbeef"))

    assert {:error, :transaction_mismatch} =
             SubjectPaymentRpcClient.confirm(envelope, @hash, @approval_hash)
  end

  test "distinguishes reverted and pending receipts without mutating state" do
    envelope = payment_link_envelope()

    put_success(@hash, @wallet, @factory, envelope.data, [
      payment_link_created_log(@factory, @subject_id, @receiver)
    ])

    Process.put(:receipts, put_in(Process.get(:receipts)[@hash]["status"], "0x0"))

    assert {:error, :transaction_reverted} =
             SubjectPaymentRpcClient.confirm(envelope, @hash, nil)

    Process.put(:receipts, %{@hash => nil})

    assert {:error, :transaction_pending} =
             SubjectPaymentRpcClient.confirm(envelope, @hash, nil)
  end

  test "rejects chain 1 and uses only the injected invalid-endpoint client" do
    envelope = payment_link_envelope()

    put_success(@hash, @wallet, @factory, envelope.data, [
      payment_link_created_log(@factory, @subject_id, @receiver)
    ])

    Process.put(:chain_id, "0x1")

    assert {:error, :wrong_chain} = SubjectPaymentRpcClient.confirm(envelope, @hash, nil)

    source = File.read!("test/ash_platform/autolaunch/subject_payment_rpc_client_test.exs")
    assert source =~ ":autolaunch_subject_payment_http_client"
    assert source =~ "chain.invalid"
  end

  test "requires the matching PaymentLinkCreated receipt log and ignores non-factory emitters" do
    envelope = payment_link_envelope()
    put_success(@hash, @wallet, @factory, envelope.data)

    assert {:error, :payment_link_created_event_missing} =
             SubjectPaymentRpcClient.confirm(envelope, @hash, nil)

    put_success(@hash, @wallet, @factory, envelope.data, [
      payment_link_created_log(@splitter, @subject_id, @receiver)
    ])

    assert {:error, :payment_link_created_event_missing} =
             SubjectPaymentRpcClient.confirm(envelope, @hash, nil)

    wrong_subject = "0x" <> String.duplicate("54", 32)

    put_success(@hash, @wallet, @factory, envelope.data, [
      payment_link_created_log(@factory, wrong_subject, @receiver)
    ])

    assert {:error, :payment_link_created_event_missing} =
             SubjectPaymentRpcClient.confirm(envelope, @hash, nil)
  end

  test "rejects structurally incomplete PaymentLinkCreated logs" do
    envelope = payment_link_envelope()
    valid_log = payment_link_created_log(@factory, @subject_id, @receiver)

    missing_creator = %{valid_log | "topics" => Enum.take(valid_log["topics"], 3)}
    put_success(@hash, @wallet, @factory, envelope.data, [missing_creator])

    assert {:error, :payment_link_created_event_missing} =
             SubjectPaymentRpcClient.confirm(envelope, @hash, nil)

    empty_data = %{valid_log | "data" => "0x"}
    put_success(@hash, @wallet, @factory, envelope.data, [empty_data])

    assert {:error, :payment_link_created_event_missing} =
             SubjectPaymentRpcClient.confirm(envelope, @hash, nil)

    truncated_data = %{
      valid_log
      | "data" => String.slice(valid_log["data"], 0, byte_size(valid_log["data"]) - 64)
    }

    put_success(@hash, @wallet, @factory, envelope.data, [truncated_data])

    assert {:error, :payment_link_created_event_missing} =
             SubjectPaymentRpcClient.confirm(envelope, @hash, nil)
  end

  defp payment_link_envelope do
    salt = "0x" <> String.duplicate("ab", 32)
    data = SubjectPaymentAbi.encode_payment_link_create(@subject_id, "Sponsor", salt, false)

    Envelope.new("create_payment_link", @wallet, data,
      to: @factory,
      resource: "autolaunch_payment_link",
      contract_name: "PaymentLinkFactory",
      risk_copy: "Create this payment link.",
      arguments: %{
        subject_id: @subject_id,
        factory: @factory,
        label: "Sponsor",
        canonical: false,
        salt: salt
      }
    )
  end

  defp stake_envelope do
    amount = 10 ** 18
    data = SubjectPaymentAbi.encode_stake(amount, @wallet)
    approval_data = SubjectPaymentAbi.encode_approval(@splitter, amount)

    Envelope.new("stake", @wallet, data,
      to: @splitter,
      resource: "autolaunch_subject_staking",
      contract_name: "RevenueShareSplitterV2",
      risk_copy: "Stake this subject token.",
      approval: %{
        token: @token,
        spender: @splitter,
        amount: Integer.to_string(amount),
        data: approval_data,
        mode: "exact"
      },
      arguments: %{
        subject_id: @subject_id,
        splitter: @splitter,
        token: @token,
        amount_atomic: Integer.to_string(amount),
        receiver: @wallet
      }
    )
  end

  defp put_success(hash, from, to, input, logs \\ []) do
    Process.put(
      :receipts,
      Map.put(Process.get(:receipts, %{}), hash, %{
        "status" => "0x1",
        "blockNumber" => "0x10",
        "transactionHash" => hash,
        "logs" => logs
      })
    )

    Process.put(
      :transactions,
      Map.put(Process.get(:transactions, %{}), hash, %{
        "hash" => hash,
        "from" => from,
        "to" => to,
        "input" => input,
        "value" => "0x0"
      })
    )
  end

  defp payment_link_created_log(emitter, subject_id, receiver) do
    %{
      "address" => emitter,
      "topics" => [
        SubjectPaymentAbi.payment_link_created_topic0(),
        subject_id,
        indexed_address(receiver),
        indexed_address(@wallet)
      ],
      "data" => payment_link_created_data("Sponsor", false)
    }
  end

  defp payment_link_created_data(label, canonical) do
    label_hex = Base.encode16(label, case: :lower)
    padded_label_size = div(byte_size(label) + 31, 32) * 32

    "0x" <>
      uint256_word(64) <>
      uint256_word(if(canonical, do: 1, else: 0)) <>
      uint256_word(byte_size(label)) <>
      String.pad_trailing(label_hex, padded_label_size * 2, "0")
  end

  defp uint256_word(value),
    do: value |> Integer.to_string(16) |> String.pad_leading(64, "0")

  defp indexed_address(address),
    do: "0x" <> String.duplicate("0", 24) <> String.trim_leading(address, "0x")

  defp restore(key, nil), do: Application.delete_env(:ash_platform, key)
  defp restore(key, value), do: Application.put_env(:ash_platform, key, value)
end
