defmodule RegentPayments.FeeForwardTest do
  @moduledoc """
  A paid fix's fee goes from the operator wallet to the REGENT staking
  contract: an approval of exactly the fee, then the deposit, each signed with
  the operator key and sent to a fake Base.
  """

  use ExUnit.Case, async: false

  import Plug.Conn

  alias Ethers.Contracts.ERC20
  alias Ethers.Transaction
  alias RegentPayments.FeeForward
  alias RegentPayments.FeeForward.Staking
  alias RegentPayments.Steps
  alias RegentPayments.Test.Actor
  alias RegentPayments.Test.PublishOffer
  alias RegentPayments.USDC

  @staking "0x" <> String.duplicate("b", 40)
  @payer "0x" <> String.duplicate("a", 40)
  @source_tag "patchbay.assist" <> String.duplicate(<<0>>, 17)

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(RegentPayments.TestRepo)
    :ok
  end

  test "the fee is approved to the staking contract and deposited, tagged and referenced" do
    {chain, signer} = chain(receipts: fn _hash -> "0x1" end)
    intent = paid_intent(signer)

    assert {:ok, %{approval: approval_hash, deposit: deposit_hash}} = forward(intent, signer)
    assert approval_hash == hash(1)
    assert deposit_hash == hash(2)
    assert [approve, deposit] = sent(chain)

    assert approve.nonce == 0
    assert approve.to == String.downcase(USDC.asset())
    assert approve.input == ERC20.approve(@staking, 100_000).data

    assert deposit.nonce == 1
    assert deposit.to == @staking

    payer_bytes = :binary.copy(<<0xAA>>, 20)

    assert deposit.input ==
             Staking.deposit_usdc(100_000, @source_tag, <<0::size(96), payer_bytes::binary>>).data
  end

  test "an approval the chain refuses deposits nothing" do
    {chain, signer} = chain(receipts: fn _hash -> "0x0" end)
    intent = paid_intent(signer)

    assert {:error, {:approval_failed, approval_hash}} = forward(intent, signer)
    assert approval_hash == hash(1)
    assert [_approve] = sent(chain)
  end

  test "a payment with no receipt is not forwarded" do
    {chain, signer} = chain(receipts: fn _hash -> "0x1" end)
    {:ok, intent} = prepare(signer.address)

    assert {:error, :no_receipt} = forward(intent, signer)
    assert sent(chain) == []
  end

  test "only a fee of the named kind, paid into the signing wallet, is forwarded" do
    {chain, signer} = chain(receipts: fn _hash -> "0x1" end)
    {_other_chain, stranger} = chain(receipts: fn _hash -> "0x1" end)
    intent = paid_intent(signer)

    assert {:error, :wrong_kind} = forward(intent, signer, :direct)
    assert {:error, :not_paid_to_signer} = forward(intent, stranger)
    assert sent(chain) == []
  end

  defp forward(intent, signer, kind \\ :publish),
    do:
      FeeForward.submit(intent.id,
        kind: kind,
        staking: @staking,
        signer: signer,
        source_tag: "patchbay.assist"
      )

  # A fake Base: counts the operator's transactions for the nonce, hands back
  # a hash per transaction sent, and answers each receipt with `receipts`'
  # status for the hash. Every raw transaction it receives is kept.
  defp chain(receipts: receipts) do
    seen = start_supervised!({Agent, fn -> [] end}, id: make_ref())

    server =
      start_supervised!(
        Supervisor.child_spec(
          {Bandit,
           plug: fn conn, _ ->
             {:ok, body, conn} = read_body(conn)
             answer = body |> JSON.decode!() |> rpc(seen, receipts)

             conn
             |> put_resp_content_type("application/json")
             |> send_resp(200, JSON.encode!(answer))
           end,
           ip: {127, 0, 0, 1},
           port: 0},
          id: make_ref()
        )
      )

    {:ok, {_address, port}} = ThousandIsland.listener_info(server)
    key = :crypto.strong_rand_bytes(32)
    {:ok, address} = X402.EIP3009.derive_address(key)

    signer = %{
      address: address,
      private_key: Base.encode16(key, case: :lower),
      rpc_url: "http://127.0.0.1:#{port}"
    }

    {seen, signer}
  end

  defp rpc(requests, seen, receipts) when is_list(requests),
    do: Enum.map(requests, &rpc(&1, seen, receipts))

  defp rpc(%{"id" => id, "method" => method} = request, seen, receipts) do
    result =
      case method do
        "eth_chainId" ->
          "0x7a69"

        "eth_getTransactionCount" ->
          "0x" <> Integer.to_string(length(Agent.get(seen, & &1)), 16)

        "eth_estimateGas" ->
          "0x186a0"

        "eth_gasPrice" ->
          "0x3b9aca00"

        "eth_maxPriorityFeePerGas" ->
          "0x1"

        "eth_feeHistory" ->
          %{
            oldestBlock: "0x0",
            baseFeePerGas: ["0x1", "0x1"],
            gasUsedRatio: [0.5],
            reward: [["0x1"]]
          }

        "eth_sendRawTransaction" ->
          [raw] = request["params"]
          Agent.update(seen, &(&1 ++ [raw]))
          hash(length(Agent.get(seen, & &1)))

        "eth_getTransactionReceipt" ->
          [hash] = request["params"]
          %{"transactionHash" => hash, "status" => receipts.(hash)}
      end

    %{jsonrpc: "2.0", id: id, result: result}
  end

  defp hash(n), do: "0x" <> String.pad_leading(Integer.to_string(n, 16), 64, "0")

  # The transactions the fake chain received, decoded, in the order sent.
  defp sent(seen) do
    seen
    |> Agent.get(& &1)
    |> Enum.map(fn raw ->
      {:ok, %Transaction.Signed{payload: payload}} = Transaction.decode(raw)
      %{payload | to: String.downcase(payload.to)}
    end)
  end

  defp payer, do: %Actor{id: Ecto.UUID.generate(), wallet_address: @payer}

  defp prepare(pay_to, actor \\ payer()) do
    RegentPayments.prepare_payment_intent(
      PublishOffer,
      %{amount_atomic: 100_000, pay_to: pay_to, target_id: Ecto.UUID.generate()},
      actor: actor
    )
  end

  # A fee paid into the operator wallet that signs, settled the way `Purchase`
  # settles one, whose receipt names the payer wallet.
  defp paid_intent(signer) do
    actor = payer()

    {:ok, intent} = prepare(signer.address, actor)
    {:ok, pending} = Steps.step(intent, :mark_settlement_pending, actor)
    tx = "0x" <> String.duplicate("e", 64)

    {:ok, _receipt} =
      Steps.record_receipt(
        %{
          payment_intent_id: pending.id,
          payment_identifier: pending.payment_identifier,
          payer_address: @payer,
          network: pending.network,
          asset: pending.asset,
          amount_atomic: pending.amount_atomic,
          facilitator: "https://example.invalid/facilitator",
          transaction_hash: tx,
          payment_response: %{"success" => true, "transaction" => tx},
          settled_at: DateTime.utc_now()
        },
        actor
      )

    {:ok, settled} = Steps.step(pending, :mark_settled, actor)
    settled
  end
end
