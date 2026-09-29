defmodule RegentPayments.RecordsTest do
  @moduledoc """
  Who may read a payment record, and what a profile's settled payments add up
  to. A wallet paying another wallet directly carries nothing on chain that
  says which profile sent it; the intent behind each settled receipt does.
  """

  use ExUnit.Case, async: false

  alias RegentPayments.Steps
  alias RegentPayments.Test.Actor
  alias RegentPayments.Test.DirectOffer
  alias RegentPayments.Test.PublishOffer

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(RegentPayments.TestRepo)
    payer = actor("a")
    other = actor("b")
    %{payer: payer, other: other, intent: prepare!(DirectOffer, payer, other.id, 1_000_000)}
  end

  test "named reads and row locks reveal an intent only to its payer", c do
    for read <- [&RegentPayments.get_payment_intent/2, &RegentPayments.lock_payment_intent/2] do
      assert {:ok, found} = read.(c.intent.id, actor: c.payer)
      assert found.payload == c.intent.payload
      assert found.id == c.intent.id

      assert {:error, _} = read.(c.intent.id, actor: c.other)
      assert {:error, _} = read.(c.intent.id, actor: nil)
    end

    assert {:ok, unchanged} = RegentPayments.get_payment_intent(c.intent.id, actor: c.payer)
    assert unchanged.status == :prepared
    assert unchanged.payload_digest == c.intent.payload_digest
  end

  test "another payer cannot tell an intent from one that does not exist", c do
    assert {:error, :not_found} = RegentPayments.Purchase.read(c.other, c.intent.id)
    assert {:error, :not_found} = RegentPayments.Purchase.read(c.other, Ecto.UUID.generate())
    assert {:error, :not_found} = RegentPayments.Purchase.read(c.payer, "not-an-id")
    assert {:ok, _found} = RegentPayments.Purchase.read(c.payer, c.intent.id)

    assert {:error, :not_found} =
             RegentPayments.Purchase.execute(c.other, c.intent.id, unsigned())

    assert {:ok, unchanged} = RegentPayments.get_payment_intent(c.intent.id, actor: c.payer)
    assert unchanged.status == :prepared
  end

  test "an intent the offer does not take from this payer stays hidden", c do
    wallet_door = %{c.payer | origin: :wallet}

    assert {:error, %Ash.Error.Forbidden{}} =
             RegentPayments.prepare_payment_intent(
               DirectOffer,
               terms(c.other.id, 1_000_000),
               actor: wallet_door
             )

    assert {:error, :not_found} = RegentPayments.Purchase.read(wallet_door, c.intent.id)

    assert {:ok, _} =
             RegentPayments.prepare_payment_intent(PublishOffer, terms(c.other.id, 1_000_000),
               actor: wallet_door
             )
  end

  test "an offer the site does not register is refused", c do
    assert {:error, error} =
             RegentPayments.prepare_payment_intent(
               RegentPayments.Test.Actor,
               terms(c.other.id, 1_000_000),
               actor: c.payer
             )

    assert %Ash.Error.Invalid{} = error
    assert Exception.message(error) =~ "is not an offer this site takes"
  end

  test "the offer's own limits refuse the terms before anything is written", c do
    assert {:error, %Ash.Error.Invalid{} = error} =
             RegentPayments.prepare_payment_intent(DirectOffer, terms(c.other.id, 1),
               actor: c.payer
             )

    assert Exception.message(error) =~ "must be between 0.01 and 100.00 USDC"
  end

  test "each site reads only its own payment records", c do
    receipt(c.intent, c.payer)
    site = Application.fetch_env!(:regent_payments, :site)
    Application.put_env(:regent_payments, :site, "another-site")
    on_exit(fn -> Application.put_env(:regent_payments, :site, site) end)

    assert {:error, _} = RegentPayments.get_payment_intent(c.intent.id, actor: c.payer)
    assert {:ok, []} = Ash.read(RegentPayments.PaymentReceipt, actor: c.payer)
    assert {:ok, %{given_count: 0}} = RegentPayments.settled_record(:direct, c.payer.id)
  end

  test "a receipt is read only by the payer of its intent", c do
    receipt(c.intent, c.payer)
    assert {:ok, [_receipt]} = Ash.read(RegentPayments.PaymentReceipt, actor: c.payer)
    assert {:ok, []} = Ash.read(RegentPayments.PaymentReceipt, actor: c.other)
  end

  test "a settled receipt is recovered without submitting another payment", c do
    stored = receipt(c.intent, c.payer)
    assert {:ok, locked} = RegentPayments.lock_payment_intent(c.intent.id, actor: c.payer)
    assert locked.receipt.id == stored.id

    assert {:applied, applied, recovered} =
             RegentPayments.Purchase.execute(c.payer, c.intent.id, unsigned())

    assert applied.status == :applied
    assert recovered.transaction_hash == stored.transaction_hash
  end

  describe "a receipt is written only for the settlement it records" do
    test "an intent that is not waiting on a settlement is refused", c do
      assert {:error, %Ash.Error.Invalid{} = error} = record(c.intent, c.payer)
      assert Exception.message(error) =~ "is not waiting on a settlement"
    end

    test "another payment's identifier is refused", c do
      {:ok, pending} = Steps.step(c.intent, :mark_settlement_pending, c.payer)
      other = prepare!(DirectOffer, c.payer, c.other.id, 1_000_000)

      assert {:error, %Ash.Error.Invalid{} = error} =
               record(pending, c.payer, payment_identifier: other.payment_identifier)

      assert Exception.message(error) =~ "is not this payment intent's"
    end

    test "another payer's or another site's intent is refused", c do
      {:ok, pending} = Steps.step(c.intent, :mark_settlement_pending, c.payer)
      assert {:error, %Ash.Error.Invalid{}} = record(pending, c.other)

      site = Application.fetch_env!(:regent_payments, :site)
      Application.put_env(:regent_payments, :site, "another-site")
      on_exit(fn -> Application.put_env(:regent_payments, :site, site) end)
      assert {:error, %Ash.Error.Invalid{} = error} = record(pending, c.payer)
      assert Exception.message(error) =~ "is not a payment intent on this site"
    end
  end

  describe "counting a profile's settled payments" do
    test "a profile that has never paid and never been paid counts nothing", c do
      assert {:ok, record} = RegentPayments.settled_record(:direct, actor("c").id)

      assert record == %{
               given_count: 0,
               given_atomic: 0,
               received_count: 0,
               received_atomic: 0
             }

      assert {:ok, %{given_count: 0}} = RegentPayments.settled_record(:direct, c.payer.id)
    end

    test "the counts separate what a profile sent from what it was sent" do
      generous = actor("c")
      helper = actor("d")
      stranger = actor("e")

      paid(generous, helper, 1_000_000)
      paid(generous, helper, 2_500_000)
      paid(stranger, generous, 500_000)

      assert {:ok, giver} = RegentPayments.settled_record(:direct, generous.id)
      assert giver.given_count == 2
      assert giver.given_atomic == 3_500_000
      assert giver.received_count == 1
      assert giver.received_atomic == 500_000

      assert {:ok, taker} = RegentPayments.settled_record(:direct, helper.id)

      assert taker == %{
               given_count: 0,
               given_atomic: 0,
               received_count: 2,
               received_atomic: 3_500_000
             }

      assert {:ok, %{given_count: 0}} = RegentPayments.settled_record(:publish, generous.id)

      assert {:ok, by_target} =
               RegentPayments.settled_by_target(:direct, [helper.id, generous.id, stranger.id])

      assert by_target == %{helper.id => 3_500_000, generous.id => 500_000}
      assert {:ok, %{}} = RegentPayments.settled_by_target(:direct, [])
    end
  end

  defp paid(from, to, amount_atomic),
    do: receipt(prepare!(DirectOffer, from, to.id, amount_atomic), from)

  defp actor(letter),
    do: %Actor{id: Ecto.UUID.generate(), wallet_address: "0x" <> String.duplicate(letter, 40)}

  defp terms(target_id, amount_atomic),
    do: %{
      amount_atomic: amount_atomic,
      pay_to: "0x" <> String.duplicate("9", 40),
      target_id: target_id
    }

  defp prepare!(offer, payer, target_id, amount_atomic) do
    {:ok, intent} =
      RegentPayments.prepare_payment_intent(offer, terms(target_id, amount_atomic), actor: payer)

    intent
  end

  defp unsigned, do: %{payment: nil, payer: nil, context: %{}}

  # A payment settled the way `Purchase` settles one: sent for settlement,
  # its receipt written, and then marked settled.
  defp receipt(intent, payer) do
    {:ok, pending} = Steps.step(intent, :mark_settlement_pending, payer)
    {:ok, receipt} = record(pending, payer)
    {:ok, _settled} = Steps.step(pending, :mark_settled, payer)
    receipt
  end

  defp record(intent, payer, changes \\ []) do
    hash = "0x" <> Base.encode16(:crypto.strong_rand_bytes(32), case: :lower)

    %{
      payment_intent_id: intent.id,
      payment_identifier: intent.payment_identifier,
      payer_address: payer.wallet_address,
      network: intent.network,
      asset: intent.asset,
      amount_atomic: intent.amount_atomic,
      facilitator: "https://example.invalid/facilitator",
      transaction_hash: hash,
      payment_response: %{"success" => true, "transaction" => hash},
      settled_at: DateTime.utc_now()
    }
    |> Map.merge(Map.new(changes))
    |> Steps.record_receipt(payer)
  end
end
