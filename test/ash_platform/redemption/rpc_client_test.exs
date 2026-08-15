defmodule AshPlatform.Redemption.RpcClientTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias AshPlatform.Redemption.RpcClient
  alias AshPlatform.WalletActions.{Envelope, RedemptionAbi}

  @wallet "0x1111111111111111111111111111111111111111"
  @other "0x2222222222222222222222222222222222222222"
  @tx_hash "0x" <> String.duplicate("ab", 32)

  defmodule HttpStub do
    alias AshPlatform.WalletActions.RedemptionAbi

    def post(_url, opts) do
      request = opts[:json]
      {:ok, %{status: 200, body: %{"jsonrpc" => "2.0", "id" => 1, "result" => result(request)}}}
    end

    defp result(%{method: "eth_chainId"}), do: "0x2105"

    defp result(%{method: "eth_getTransactionReceipt"}),
      do: Application.get_env(:ash_platform, :test_redemption_receipt)

    defp result(%{method: "eth_getTransactionByHash"}),
      do: Application.get_env(:ash_platform, :test_redemption_transaction)

    defp result(%{method: "eth_call", params: [%{data: data} | _]}) do
      overrides = Application.get_env(:ash_platform, :test_redemption_rpc_overrides, %{})
      Map.get(overrides, data, default_call(data))
    end

    defp default_call(data) do
      cond do
        data == RedemptionAbi.encode_read("animata_i") ->
          word_address(RedemptionAbi.animata_i_address())

        data == RedemptionAbi.encode_read("animata_ii") ->
          word_address(RedemptionAbi.animata_ii_address())

        data == RedemptionAbi.encode_read("result_collection") ->
          word_address(RedemptionAbi.result_collection_address())

        data == RedemptionAbi.encode_read("usdc") ->
          word_address(RedemptionAbi.usdc_address())

        data == RedemptionAbi.encode_read("regent") ->
          word_address(RedemptionAbi.regent_address())

        data in [RedemptionAbi.encode_read("usdc_price"), RedemptionAbi.encode_read("price")] ->
          word_uint(80_000_000)

        data == RedemptionAbi.encode_read("regent_payout") ->
          word_uint(5_000_000 * Integer.pow(10, 18))

        data == RedemptionAbi.encode_read("vest_duration") ->
          word_uint(604_800)

        data == RedemptionAbi.encode_read("max_source_token_id") ->
          word_uint(999)

        String.starts_with?(data, "0x70a08231") ->
          word_uint(100_000_000)

        String.starts_with?(data, "0xdd62ed3e") ->
          word_uint(80_000_000)

        String.starts_with?(data, "0x402914f5") ->
          word_uint(2 * Integer.pow(10, 18))

        String.starts_with?(data, "0x474fc417") ->
          words([
            5_000_000 * Integer.pow(10, 18),
            2 * Integer.pow(10, 18),
            Integer.pow(10, 18),
            1_700_000_000
          ])

        String.starts_with?(data, "0x6352211e") ->
          word_address("0x1111111111111111111111111111111111111111")

        String.starts_with?(data, "0xe985e9c5") ->
          word_uint(1)

        String.starts_with?(data, "0x6d970989") ->
          word_uint(1123)

        true ->
          word_uint(0)
      end
    end

    defp words(values),
      do: "0x" <> Enum.map_join(values, &String.pad_leading(Integer.to_string(&1, 16), 64, "0"))

    defp word_uint(value), do: "0x" <> String.pad_leading(Integer.to_string(value, 16), 64, "0")

    defp word_address(address),
      do: "0x" <> (address |> String.trim_leading("0x") |> String.pad_leading(64, "0"))
  end

  defmodule TimeoutStub do
    def post(_url, _opts), do: {:error, %Req.TransportError{reason: :timeout}}
  end

  defmodule SlowStub do
    def post(_url, _opts) do
      Process.sleep(100)
      {:ok, %{status: 200, body: %{"result" => "0x2105"}}}
    end
  end

  setup do
    previous_http = Application.get_env(:ash_platform, :redemption_http_client)
    previous_url = Application.get_env(:ash_platform, :base_read_rpc_url)
    previous_timeout = Application.get_env(:ash_platform, :redemption_overview_timeout)

    Application.put_env(:ash_platform, :redemption_http_client, HttpStub)
    Application.put_env(:ash_platform, :base_read_rpc_url, "https://provider.invalid/private-key")

    on_exit(fn ->
      restore(:redemption_http_client, previous_http)
      restore(:base_read_rpc_url, previous_url)
      restore(:redemption_overview_timeout, previous_timeout)

      for key <- [
            :test_redemption_receipt,
            :test_redemption_transaction,
            :test_redemption_rpc_overrides
          ],
          do: Application.delete_env(:ash_platform, key)
    end)

    :ok
  end

  test "public and account reads verify every pinned constant and decode status" do
    assert {:ok, public} = RpcClient.overview(nil, nil, nil)
    assert public.chain_id == 8453
    assert public.wallet_address == nil
    assert public.price_raw == "80000000"
    assert public.payout == "5000000"
    assert public.regent_address == String.downcase(RedemptionAbi.regent_address())

    collection = String.downcase(RedemptionAbi.animata_i_address())
    assert {:ok, account} = RpcClient.overview(@wallet, collection, 42)
    assert account.nft_owner == @wallet
    assert account.nft_approved
    assert account.usdc_balance_raw == "100000000"
    assert account.usdc_allowance_raw == "80000000"
    assert account.claimable == "2"
    assert account.vest_pool == "5000000"
    assert account.vest_released == "2"
    assert account.vest_claimed == "1"
    assert account.vest_start == 1_700_000_000
    assert account.result_token_id == 1123

    assert {:ok, approval_view} = RpcClient.overview(@wallet, collection, nil)
    assert approval_view.nft_approved
    assert approval_view.nft_owner == nil
    assert approval_view.token_id == nil
    assert approval_view.claimable == "2"
  end

  test "a constant mismatch fails the entire read" do
    Application.put_env(:ash_platform, :test_redemption_rpc_overrides, %{
      RedemptionAbi.encode_read("regent") => word_address(@other)
    })

    assert {:error, :contract_constants_mismatch} = RpcClient.overview(nil, nil, nil)
  end

  test "confirmation requires exact transaction identity for success and revert" do
    envelope =
      Envelope.new("claim", @wallet, RedemptionAbi.encode_action("claim", []),
        resource: "animata_redemption",
        to: RedemptionAbi.redeemer_address(),
        contract_name: "AnimataRedeemer",
        risk_copy: "Claim unlocked REGENT.",
        arguments: %{}
      )

    put_receipt("0x1")
    put_transaction(envelope)

    assert {:ok, %{transaction_hash: @tx_hash, receipt_verified: true}} =
             RpcClient.confirm(envelope, @tx_hash)

    Application.put_env(:ash_platform, :test_redemption_transaction, %{
      "hash" => @tx_hash,
      "from" => @other,
      "to" => envelope.to,
      "input" => envelope.data,
      "value" => "0x0"
    })

    assert {:error, :transaction_mismatch} = RpcClient.confirm(envelope, @tx_hash)

    put_receipt("0x0")
    assert {:error, :transaction_mismatch} = RpcClient.confirm(envelope, @tx_hash)

    put_transaction(envelope)
    assert {:error, :transaction_reverted} = RpcClient.confirm(envelope, @tx_hash)

    Application.put_env(:ash_platform, :test_redemption_receipt, %{
      "status" => "0x0",
      "transactionHash" => @tx_hash
    })

    assert {:error, :invalid_receipt} = RpcClient.confirm(envelope, @tx_hash)

    put_receipt("0x1")
    put_transaction(envelope, &Map.put(&1, "hash", "0x" <> String.duplicate("ef", 32)))
    assert {:error, :transaction_mismatch} = RpcClient.confirm(envelope, @tx_hash)

    put_transaction(envelope, &Map.delete(&1, "hash"))
    assert {:error, :transaction_mismatch} = RpcClient.confirm(envelope, @tx_hash)

    for change <- [
          fn tx -> %{tx | "to" => @other} end,
          fn tx -> %{tx | "input" => "0xdeadbeef"} end,
          fn tx -> %{tx | "value" => "0x1"} end
        ] do
      put_receipt("0x1")
      put_transaction(envelope, change)
      assert {:error, :transaction_mismatch} = RpcClient.confirm(envelope, @tx_hash)
    end
  end

  # The reread is `allowance(wallet_address, redeemer_address)`. An envelope that
  # intended a different spender is answered by a number about somebody else, so
  # the spender is compared as explicitly as the owner, token and exact amount.
  test "RECEIPT_AND_REREAD_BOTH_REQUIRED: exact-USDC approval compares owner, token, spender and amount" do
    redeemer = RedemptionAbi.redeemer_address()
    exact = String.to_integer(RedemptionAbi.price_atomic())

    intended = usdc_approval_envelope(redeemer, exact)
    put_receipt("0x1")
    put_transaction(intended)

    assert {:ok, %{receipt_verified: true, reread_verified: true, reason: nil}} =
             RpcClient.confirm(intended, @tx_hash)

    for drifted <- [
          usdc_approval_envelope(@other, exact),
          usdc_approval_envelope(redeemer, exact + 1)
        ] do
      put_transaction(drifted)

      assert {:ok,
              %{
                receipt_verified: true,
                reread_verified: false,
                reason: :usdc_allowance_not_current
              }} = RpcClient.confirm(drifted, @tx_hash)
    end
  end

  test "timeouts are bounded and transport logs never reveal the provider URL" do
    Application.put_env(:ash_platform, :redemption_http_client, TimeoutStub)

    log =
      capture_log(fn ->
        assert {:error, :chain_unavailable} = RpcClient.overview(nil, nil, nil)
      end)

    assert log =~ "redemption chain read failed"
    refute log =~ "private-key"
    refute log =~ "provider.invalid"

    Application.put_env(:ash_platform, :redemption_http_client, SlowStub)
    Application.put_env(:ash_platform, :redemption_overview_timeout, 10)
    assert {:error, :chain_timeout} = RpcClient.overview(nil, nil, nil)
  end

  defp usdc_approval_envelope(spender, amount) do
    Envelope.new(
      "approve_exact_usdc",
      @wallet,
      RedemptionAbi.encode_erc20("approve", [spender, amount]),
      resource: "animata_redemption",
      to: RedemptionAbi.usdc_address(),
      contract_name: "USDC",
      risk_copy: "Approve exactly 80 USDC for the verified Animata redeemer.",
      arguments: %{
        spender: String.downcase(spender),
        amount_atomic: Integer.to_string(amount),
        mode: "exact"
      }
    )
  end

  defp put_receipt(status) do
    Application.put_env(:ash_platform, :test_redemption_receipt, %{
      "status" => status,
      "blockNumber" => "0x10",
      "transactionHash" => @tx_hash
    })
  end

  defp put_transaction(envelope, change \\ &Function.identity/1) do
    transaction = %{
      "hash" => @tx_hash,
      "from" => @wallet,
      "to" => envelope.to,
      "input" => envelope.data,
      "value" => "0x0"
    }

    Application.put_env(:ash_platform, :test_redemption_transaction, change.(transaction))
  end

  defp word_address(address),
    do: "0x" <> (address |> String.trim_leading("0x") |> String.pad_leading(64, "0"))

  defp restore(key, nil), do: Application.delete_env(:ash_platform, key)
  defp restore(key, value), do: Application.put_env(:ash_platform, key, value)
end
