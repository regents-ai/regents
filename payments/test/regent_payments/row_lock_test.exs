defmodule RegentPayments.RowLockTest do
  @moduledoc """
  Two callers resume one settled payment at the same moment, each on its own
  database connection as two machines would. The second waits on the intent's
  row lock while the first carries the effect out, then finds the intent
  applied: the site's row is saved once.

  The sandbox shares one connection between processes, which would hide the
  lock, so this case commits its rows for real and removes them afterwards.
  """

  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias RegentPayments.Purchase
  alias RegentPayments.Steps
  alias RegentPayments.Test.Actor
  alias RegentPayments.Test.DirectOffer
  alias RegentPayments.Test.Effects
  alias RegentPayments.TestRepo

  setup do
    payer = %Actor{id: Ecto.UUID.generate(), wallet_address: "0x" <> String.duplicate("c", 40)}
    intent = unboxed(fn -> settled!(payer) end)
    on_exit(fn -> unboxed(fn -> remove!(intent.id) end) end)
    %{payer: payer, intent: intent}
  end

  test "two connections resuming one payment carry it out exactly once", c do
    parent = self()
    request = %{payment: nil, payer: nil, context: %{watcher: parent}}
    resume = fn -> unboxed(fn -> Purchase.execute(c.payer, c.intent.id, request) end) end

    first = Task.async(resume)
    assert_receive {:carrying, carrier}, 3_000
    second = Task.async(resume)

    assert waits_on_a_lock?(40)
    refute_received {:carrying, _}
    send(carrier, :go)

    assert [{:applied, _, first_receipt}, {:applied, _, second_receipt}] =
             Task.await_many([first, second], 5_000)

    assert first_receipt.id == second_receipt.id
    refute_received {:carrying, _}
    assert unboxed(fn -> Effects.carried_out(c.intent.id) end) == 1
  end

  defp unboxed(fun), do: Sandbox.unboxed_run(TestRepo, fun)

  # A settled payment whose effect has not been carried out yet.
  defp settled!(payer) do
    terms = %{
      amount_atomic: 1_000_000,
      pay_to: "0x" <> String.duplicate("9", 40),
      target_id: Ecto.UUID.generate()
    }

    {:ok, intent} = RegentPayments.prepare_payment_intent(DirectOffer, terms, actor: payer)
    {:ok, pending} = Steps.step(intent, :mark_settlement_pending, payer)
    hash = "0x" <> Base.encode16(:crypto.strong_rand_bytes(32), case: :lower)

    {:ok, _receipt} =
      Steps.record_receipt(
        %{
          payment_intent_id: pending.id,
          payer_address: payer.wallet_address,
          network: pending.network,
          asset: pending.asset,
          amount_atomic: pending.amount_atomic,
          facilitator: "https://example.invalid/facilitator",
          transaction_hash: hash,
          payment_response: %{"success" => true, "transaction" => hash},
          settled_at: DateTime.utc_now()
        },
        payer
      )

    {:ok, settled} = Steps.step(pending, :mark_settled, payer)
    settled
  end

  # Whether another session on this database is waiting on a lock, asked every
  # 50 ms up to `tries` times.
  defp waits_on_a_lock?(0), do: false

  defp waits_on_a_lock?(tries) do
    %{rows: [[waiting]]} =
      unboxed(fn ->
        TestRepo.query!(
          "SELECT count(*) FROM pg_stat_activity " <>
            "WHERE datname = current_database() AND wait_event_type = 'Lock'"
        )
      end)

    waiting > 0 or (Process.sleep(50) || waits_on_a_lock?(tries - 1))
  end

  # This case's own rows, and only those, from its own test database.
  defp remove!(intent_id) do
    id = Ecto.UUID.dump!(intent_id)
    TestRepo.query!("DELETE FROM payment_effects WHERE payment_intent_id = $1", [id])

    TestRepo.query!(
      "DELETE FROM regent_payments.payment_receipts WHERE payment_intent_id = $1",
      [id]
    )

    TestRepo.query!("DELETE FROM regent_payments.payment_intents WHERE id = $1", [id])
  end
end
