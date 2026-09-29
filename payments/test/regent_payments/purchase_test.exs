defmodule RegentPayments.PurchaseTest do
  @moduledoc """
  Paying for an intent from a page's wallet and over x402, against a loopback
  facilitator that answers each settlement when the test says so. The intent
  is settled at most once whatever the caller, the facilitator or the
  database does, and a refused payment never reaches the facilitator.

  Every process in a case shares the case's sandboxed connection, so nothing
  a case writes outlives it.
  """

  use ExUnit.Case, async: false

  import Plug.Conn

  alias Ecto.Adapters.SQL.Sandbox
  alias RegentPayments.Purchase
  alias RegentPayments.Test.Actor
  alias RegentPayments.Test.DirectOffer
  alias RegentPayments.Test.Effects
  alias RegentPayments.Test.PublishOffer
  alias RegentPayments.Test.WalletSigner
  alias RegentPayments.TestRepo
  alias RegentPayments.WalletPayment

  @facilitator RegentPayments.Facilitator

  setup do
    :ok = Sandbox.checkout(TestRepo)
    Sandbox.mode(TestRepo, {:shared, self()})
    owner = self()

    server =
      start_supervised!(
        {Bandit,
         plug: fn conn, _opts ->
           {:ok, body, conn} = read_body(conn)

           {status, answer} =
             if conn.request_path == "/verify" do
               send(owner, {:verify, JSON.decode!(body)})
               {200, %{"isValid" => true}}
             else
               send(owner, {:settle, self(), JSON.decode!(body)})

               receive do
                 {:reply, status, answer} -> {status, answer}
               after
                 5_000 -> {503, %{error: "fixture timeout"}}
               end
             end

           conn
           |> put_resp_content_type("application/json")
           |> send_resp(status, JSON.encode!(answer))
         end,
         ip: {127, 0, 0, 1},
         port: 0}
      )

    {:ok, {_address, port}} = ThousandIsland.listener_info(server)
    original = Application.fetch_env!(:regent_payments, @facilitator)

    Application.put_env(
      :regent_payments,
      @facilitator,
      Keyword.put(original, :url, "http://127.0.0.1:#{port}")
    )

    on_exit(fn -> Application.put_env(:regent_payments, @facilitator, original) end)
    start_supervised!(RegentPayments.Supervisor)

    wallet = WalletSigner.new()
    payer = %Actor{id: Ecto.UUID.generate(), wallet_address: wallet.address}
    %{payer: payer, wallet: wallet, intent: prepare(DirectOffer, payer)}
  end

  test "pending commits before dispatch and a 503 never repeats settlement", c do
    {worker, ref} = execute(c)
    assert_receive {:settle, service, _payload}, 3_000
    assert status(c) == :settlement_pending
    assert {:settlement_pending, _} = pay(c, %{})
    send(service, {:reply, 503, %{error: "uncertain"}})
    assert_receive {:done, ^worker, {:settlement_pending, _}}, 3_000
    assert_receive {:DOWN, ^ref, :process, ^worker, :normal}
    refute_receive {:settle, _, _}, 200
  end

  test "a killed caller leaves a durable attempt without charging again", c do
    {worker, ref} = execute(c)
    assert_receive {:settle, service, _payload}, 3_000
    Process.exit(worker, :kill)
    assert_receive {:DOWN, ^ref, :process, ^worker, :killed}
    send(service, {:reply, 200, settled("1")})
    assert status(c) == :settlement_pending
    assert {:settlement_pending, _} = pay(c, %{})
    refute_receive {:settle, _, _}, 200
  end

  test "distinct intents settle independently and the receipt reads back", c do
    second = prepare(DirectOffer, c.payer)
    {first_worker, _} = execute(c)
    assert_receive {:settle, first_service, _}, 3_000
    {second_worker, _} = execute(%{c | intent: second})
    assert_receive {:settle, second_service, _}, 3_000
    send(second_service, {:reply, 200, settled("2")})
    assert_receive {:done, ^second_worker, {:applied, _, _}}, 3_000
    send(first_service, {:reply, 200, settled("3")})
    assert_receive {:done, ^first_worker, {:applied, applied, receipt}}, 3_000
    assert applied.status == :applied
    assert receipt.transaction_hash == settled("3")["transaction"]
    assert receipt.payer_address == c.wallet.address

    assert {:ok, found} = Purchase.read(c.payer, c.intent.id)
    assert found.receipt.transaction_hash == settled("3")["transaction"]

    stranger = %Actor{id: Ecto.UUID.generate(), wallet_address: WalletSigner.new().address}
    assert {:error, :not_found} = Purchase.read(stranger, c.intent.id)
  end

  test "a receipt that cannot be written leaves the committed pending marker", c do
    {worker, _} = execute(c)
    assert_receive {:settle, service, _}, 3_000
    name = "recovery_" <> String.replace(c.intent.id, "-", "")

    TestRepo.query!(
      "ALTER TABLE regent_payments.payment_receipts ADD CONSTRAINT #{name} CHECK (payment_intent_id <> '#{c.intent.id}'::uuid)"
    )

    send(service, {:reply, 200, settled("4")})
    await_finish(worker)
    assert status(c) == :settlement_pending
    assert {:settlement_pending, _} = pay(c, %{})
    refute_receive {:settle, _, _}, 200
  end

  test "a settled receipt survives an effect that failed and is never charged again", c do
    c = %{c | intent: prepare(PublishOffer, c.payer)}
    {worker, _} = execute(c)
    assert_receive {:settle, service, _}, 3_000
    send(service, {:reply, 200, settled("5")})
    assert_receive {:done, ^worker, {:settled, settled, receipt}}, 3_000
    assert settled.status == :settled
    assert receipt.transaction_hash == settled("5")["transaction"]

    assert {:settled, _, again} = pay(c, %{})
    assert again.id == receipt.id
    refute_receive {:settle, _, _}, 200
  end

  test "a resuming offer is carried out on the next call from the same payment", c do
    {worker, _} = execute(c, %{outcome: :incomplete})
    assert_receive {:settle, service, _}, 3_000
    send(service, {:reply, 200, settled("6")})
    assert_receive {:done, ^worker, {:settled, _, receipt}}, 3_000

    assert {:applied, applied, again} = pay(c, %{})
    assert applied.status == :applied
    assert again.id == receipt.id
    assert Effects.carried_out(c.intent.id) == 2
    refute_receive {:settle, _, _}, 200
  end

  # The case's one sandboxed connection is shared by every process, so the second
  # caller waits on that connection while the first holds it; in production it
  # waits on the intent's row lock instead. Either way it finds the intent
  # applied and carries nothing out.
  test "two callers resuming one payment at once carry it out exactly once", c do
    {worker, _} = execute(c, %{outcome: :incomplete})
    assert_receive {:settle, service, _}, 3_000
    send(service, {:reply, 200, settled("7")})
    assert_receive {:done, ^worker, {:settled, _, _}}, 3_000
    assert Effects.carried_out(c.intent.id) == 1

    parent = self()
    callers = for _ <- 1..2, do: Task.async(fn -> pay(c, %{}, %{watcher: parent}) end)
    assert_receive {:carrying, carrier}, 3_000
    refute_receive {:carrying, _}, 300
    send(carrier, :go)

    assert [{:applied, _, first}, {:applied, _, second}] = Task.await_many(callers, 5_000)
    assert first.id == second.id
    refute_received {:carrying, _}
    assert Effects.carried_out(c.intent.id) == 2
    assert status(c) == :applied
  end

  test "an effect that fails is rolled back with its applied mark and the receipt stays", c do
    {worker, _} = execute(c, %{outcome: :fail})
    assert_receive {:settle, service, _}, 3_000
    send(service, {:reply, 200, settled("8")})
    assert_receive {:done, ^worker, {:settled, settled, receipt}}, 3_000
    assert settled.status == :settled
    assert Effects.carried_out(c.intent.id) == 0

    assert {:ok, found} = Purchase.read(c.payer, c.intent.id)
    assert found.status == :settled
    assert found.receipt.id == receipt.id

    assert {:applied, _, again} = pay(c, %{})
    assert again.id == receipt.id
    assert Effects.carried_out(c.intent.id) == 1
    refute_receive {:settle, _, _}, 200
  end

  test "a settlement the facilitator has not finished is held for a person", c do
    {worker, _} = execute(c)
    assert_receive {:settle, service, _}, 3_000
    send(service, {:reply, 200, %{"success" => false, "errorReason" => "settlement_pending"}})
    assert_receive {:done, ^worker, {:settlement_pending, _}}, 3_000
    assert status(c) == :settlement_pending
  end

  test "a settlement the facilitator refuses marks the intent failed", c do
    {worker, _} = execute(c)
    assert_receive {:settle, service, _}, 3_000
    send(service, {:reply, 200, %{"success" => false, "errorReason" => "insufficient_funds"}})
    assert_receive {:done, ^worker, {:payment_refused, _, reason}}, 3_000
    assert reason == "The wallet does not hold enough USDC on Base for this payment."
    assert status(c) == :failed
  end

  test "terms that ran out are expired, never offered or paid", c do
    TestRepo.query!(
      "UPDATE regent_payments.payment_intents SET expires_at = now() - interval '1 minute' WHERE id = $1",
      [Ecto.UUID.dump!(c.intent.id)]
    )

    assert {:expired, expired} = pay(c, %{"active_wallet" => c.wallet.address})
    assert expired.status == :expired
    nothing_sent()
  end

  test "an x402 payment must come from the wallet the door names", c do
    review = review(c)
    {:ok, found} = Purchase.read(c.payer, c.intent.id)
    {:ok, payment} = WalletPayment.payment(found, c.wallet.address, signed(c.wallet, review))
    request = %{payment: payment, payer: WalletSigner.new().address, context: %{}}

    assert {:payment_rejected, _, reason} = Purchase.execute(c.payer, c.intent.id, request)
    assert reason =~ "different wallet"
    nothing_sent()
  end

  test "an x402 payment must name this payment, or none", c do
    review = review(c)
    {:ok, found} = Purchase.read(c.payer, c.intent.id)
    {:ok, payment} = WalletPayment.payment(found, c.wallet.address, signed(c.wallet, review))

    for {id, words} <- [
          {Ecto.UUID.generate(), "different payment"},
          {"short", "could not be read"}
        ] do
      naming = put_in(payment["extensions"]["payment-identifier"]["info"]["id"], id)
      request = %{payment: naming, payer: c.wallet.address, context: %{}}

      assert {:payment_rejected, _, reason} = Purchase.execute(c.payer, c.intent.id, request)
      assert reason =~ words
    end

    nothing_sent()
  end

  test "the terms name the frozen amount, wallet and payment identifier", c do
    terms = Purchase.terms(c.intent, "Payment is required.", "https://site.example/pay")
    assert [requirement] = terms["accepts"]
    assert requirement["amount"] == "1000000"
    assert requirement["payTo"] == c.intent.payload["pay_to_address"]
    assert requirement["network"] == "eip155:8453"
    assert terms["resource"]["url"] == "https://site.example/pay"
    assert terms["resource"]["description"] == c.intent.effect_summary

    assert terms["extensions"]["payment-identifier"]["info"] ==
             %{"required" => false, "id" => c.intent.payment_identifier}
  end

  # Only the wallet a review was written for can pay it, with a signature the
  # library can check; anything else is refused before the facilitator is
  # asked.
  describe "a signed payment the library refuses never reaches the facilitator" do
    test "no wallet open on the page, or none on the profile", c do
      assert {:wallet_unavailable, id} = pay(c, %{})
      assert id == c.intent.id

      walletless = %{c | payer: %{c.payer | wallet_address: nil}}
      assert {:wallet_unavailable, _} = pay(walletless, %{"active_wallet" => c.wallet.address})
      nothing_sent()
    end

    test "a signature from another key", c do
      review = review(c)

      assert {:payment_refused, _, reason} = pay(c, signed(c.wallet, review, WalletSigner.new()))
      assert reason =~ "not from the wallet"
      nothing_sent()
    end

    test "an active wallet that is not the one signed in with, unsigned and signed", c do
      stranger = WalletSigner.new()

      assert {:wallet_mismatch, _, note} = pay(c, %{"active_wallet" => stranger.address})
      assert note =~ RegentFormat.short_address(stranger.address)

      review = review(c)
      assert {:wallet_mismatch, _, _} = pay(c, signed(stranger, review))
      nothing_sent()
    end

    test "a stale review id", c do
      review = review(c)
      stale = %{signed(c.wallet, review) | "review_id" => Ecto.UUID.generate()}

      assert {:payment_refused, _, reason} = pay(c, stale)
      assert reason =~ "changed since your wallet saw them"
      nothing_sent()
    end

    test "a malformed signature", c do
      review = review(c)

      for signature <- [
            "0x1234",
            "0x" <> String.duplicate("z", 130),
            "0x" <> String.duplicate("0", 130),
            7
          ] do
        params = %{signed(c.wallet, review) | "signature" => signature}
        assert {:payment_refused, _, _} = pay(c, params)
      end

      nothing_sent()
    end
  end

  defp nothing_sent do
    refute_receive {:verify, _}, 200
    refute_receive {:settle, _, _}, 200
  end

  defp review(c) do
    assert {:review, _waiting, review} = pay(c, %{"active_wallet" => c.wallet.address})
    assert review.signer == c.wallet.address
    review
  end

  # The page's answer: its active wallet, the review it signed, and the
  # signature `signer` made over it.
  defp signed(active, review, signer \\ nil) do
    %{
      "active_wallet" => active.address,
      "review_id" => review.id,
      "signature" => WalletSigner.sign(signer || active, review)
    }
  end

  defp pay(c, params, context \\ %{}),
    do: WalletPayment.pay(c.payer, c.intent.id, params, context)

  defp status(c) do
    {:ok, found} = Purchase.read(c.payer, c.intent.id)
    found.status
  end

  defp await_finish(worker) do
    receive do
      {:done, ^worker, _answer} -> :ok
      {:DOWN, _ref, :process, ^worker, _reason} -> :ok
    after
      3_000 -> flunk("settlement caller did not finish")
    end
  end

  defp execute(c, context \\ %{}) do
    parent = self()

    spawn_monitor(fn ->
      answer = pay(c, signed(c.wallet, review(c)), context)
      send(parent, {:done, self(), answer})
    end)
  end

  defp prepare(offer, payer) do
    {:ok, intent} =
      RegentPayments.prepare_payment_intent(
        offer,
        %{
          amount_atomic: 1_000_000,
          pay_to: "0x" <> String.duplicate("b", 40),
          target_id: Ecto.UUID.generate()
        },
        actor: payer
      )

    intent
  end

  defp settled(letter),
    do: %{
      "success" => true,
      "transaction" => "0x" <> String.duplicate(letter, 64),
      "network" => "eip155:8453"
    }
end
