defmodule RegentPayments.Changes.FreezeTerms do
  @moduledoc """
  Settles the terms of a payment at the moment it is prepared: which wallet
  the money goes to, how much, what it is for, the sentence the payer is
  shown, when the offer runs out, and a digest over all of it.

  A payer signs for an amount and a destination, and what the facilitator
  settles has to be the same amount and destination they were shown. The
  site's offer works those out once, here, and nothing later asks it again,
  so a wallet changed after the fact cannot redirect a payment already offered.
  """

  use Ash.Resource.Change

  alias Ash.Error.Changes.InvalidArgument
  alias Ash.Error.Changes.InvalidChanges
  alias RegentPayments.CanonicalJSON
  alias RegentPayments.Offer

  @window_seconds 15 * 60

  @wallet_address ~r/\A0x[0-9a-fA-F]{40}\z/

  @impl true
  def change(changeset, _opts, %{actor: actor}) when not is_nil(actor) do
    with {:ok, offer} <- Offer.registered(Ash.Changeset.get_argument(changeset, :offer)),
         {:ok, terms} <- offer.freeze(Ash.Changeset.get_argument(changeset, :input), actor),
         :ok <- payable(terms) do
      freeze(changeset, offer, terms)
    else
      :error ->
        Ash.Changeset.add_error(
          changeset,
          InvalidArgument.exception(field: :offer, message: "is not an offer this site takes")
        )

      {:error, errors} ->
        Ash.Changeset.add_error(changeset, errors)
    end
  end

  # With nobody signed in there is no payer to freeze terms for; the policy
  # refuses the action.
  def change(changeset, _opts, _context), do: changeset

  # Terms with nowhere for the money to go, or no money, are no terms at all.
  defp payable(%{pay_to_address: pay_to, amount_atomic: amount})
       when is_binary(pay_to) and is_integer(amount) and amount > 0 do
    if Regex.match?(@wallet_address, pay_to),
      do: :ok,
      else: {:error, InvalidChanges.exception(message: "the terms name no wallet to be paid")}
  end

  defp payable(_terms),
    do: {:error, InvalidChanges.exception(message: "the terms name no wallet or amount")}

  defp freeze(changeset, offer, terms) do
    # The identifier is minted here rather than read back off the row, because
    # the primary key's own default is not applied until the insert itself.
    identifier = Ash.UUID.generate()

    payload =
      Map.merge(terms.payload, %{
        "pay_to_address" => terms.pay_to_address,
        "amount_atomic" => terms.amount_atomic
      })

    Ash.Changeset.force_change_attributes(changeset, %{
      id: identifier,
      payment_identifier: identifier,
      kind: offer.kind(),
      target_type: offer.target_type(),
      target_id: terms.target_id,
      amount_atomic: terms.amount_atomic,
      payload: payload,
      payload_digest: CanonicalJSON.digest(payload),
      recipient_snapshot: terms.recipient_snapshot,
      effect_summary: terms.effect_summary,
      expires_at: DateTime.add(DateTime.utc_now(), @window_seconds, :second)
    })
  end
end
