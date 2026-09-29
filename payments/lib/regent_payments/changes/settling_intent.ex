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

    case RegentPayments.get_payment_intent(id, actor: actor) do
      {:ok, %{status: :settlement_pending}} ->
        changeset

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
