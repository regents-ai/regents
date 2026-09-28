defmodule RegentPayments.Changes.SettlingIntent do
  @moduledoc """
  Holds a receipt to the intent it is written for: one this site offered to
  the actor, waiting on its settlement, and carrying the same payment
  identifier. Anything else is refused before the receipt is written, so a
  receipt can never be attached to another site's intent, to one that was
  never sent for settlement, or under another payment's identifier.
  """

  use Ash.Resource.Change

  alias Ash.Error.Changes.InvalidAttribute

  @impl true
  def change(changeset, _opts, %{actor: actor}) do
    Ash.Changeset.before_action(changeset, &settling(&1, actor))
  end

  defp settling(changeset, actor) do
    id = Ash.Changeset.get_attribute(changeset, :payment_intent_id)
    identifier = Ash.Changeset.get_attribute(changeset, :payment_identifier)

    case RegentPayments.get_payment_intent(id, actor: actor) do
      {:ok, %{status: :settlement_pending, payment_identifier: ^identifier}} ->
        changeset

      {:ok, %{status: :settlement_pending}} ->
        refuse(changeset, :payment_identifier, identifier, "is not this payment intent's")

      {:ok, _not_settling} ->
        refuse(changeset, :payment_intent_id, id, "is not waiting on a settlement")

      {:error, _not_found} ->
        refuse(changeset, :payment_intent_id, id, "is not a payment intent on this site")
    end
  end

  defp refuse(changeset, field, value, message) do
    Ash.Changeset.add_error(
      changeset,
      InvalidAttribute.exception(field: field, value: value, message: message)
    )
  end
end
