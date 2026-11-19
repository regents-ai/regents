defmodule RegentPayments.Changes.SettlingIntent do
  @moduledoc """
  Holds a receipt to the intent it is written for: one this site offered to
  the actor and waiting on its settlement. Anything else is refused before the
  receipt is written, so a receipt can never be attached to another site's
  intent or to one that was never sent for settlement.
  """

  use Ash.Resource.Change

  alias Ash.Error.Changes.InvalidAttribute

  @impl true
  def change(changeset, _opts, %{actor: actor}) do
    Ash.Changeset.before_action(changeset, &settling(&1, actor))
  end

  defp settling(changeset, actor) do
    id = Ash.Changeset.get_attribute(changeset, :payment_intent_id)

    case RegentPayments.lock_payment_intent(id, actor: actor) do
      {:ok, %{status: :settlement_pending} = intent} ->
        if matches_completion?(changeset, actor, intent),
          do: changeset,
          else:
            refuse(
              changeset,
              :payment_intent_id,
              id,
              "does not match this authorized completion"
            )

      {:ok, _not_settling} ->
        refuse(changeset, :payment_intent_id, id, "is not waiting on a settlement")

      {:error, _not_found} ->
        refuse(changeset, :payment_intent_id, id, "is not a payment intent on this site")
    end
  end

  defp matches_completion?(changeset, %{role: :payment_completion} = actor, intent) do
    expected = %{
      network: intent.network,
      asset: intent.asset,
      amount_atomic: intent.amount_atomic
    }

    payer = Ash.Changeset.get_attribute(changeset, :payer_address)

    RegentPayments.AgentAuthority.completion_for?(actor, intent, intent.kind) and
      is_binary(payer) and String.downcase(payer) == actor.wallet_address and
      Enum.all?(expected, fn {field, value} ->
        Ash.Changeset.get_attribute(changeset, field) == value
      end)
  end

  defp matches_completion?(_, _, _), do: true

  defp refuse(changeset, field, value, message) do
    Ash.Changeset.add_error(
      changeset,
      InvalidAttribute.exception(field: field, value: value, message: message)
    )
  end
end
