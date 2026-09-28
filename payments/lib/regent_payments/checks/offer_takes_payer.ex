defmodule RegentPayments.Checks.OfferTakesPayer do
  @moduledoc """
  Lets a signed-in actor prepare terms only for an offer the site registers
  and whose `c:RegentPayments.Offer.payer?/1` takes that actor.
  """

  use Ash.Policy.SimpleCheck

  alias RegentPayments.Offer

  @impl true
  def describe(_opts), do: "the offer takes this actor as its payer"

  @impl true
  def match?(nil, _context, _opts), do: false

  def match?(actor, %{subject: %Ash.Changeset{} = changeset}, _opts) do
    case Offer.registered(Ash.Changeset.get_argument(changeset, :offer)) do
      {:ok, offer} -> offer.payer?(actor)
      :error -> false
    end
  end

  def match?(_actor, _context, _opts), do: false
end
