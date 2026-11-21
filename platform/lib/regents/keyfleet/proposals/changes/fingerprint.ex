defmodule Regents.Keyfleet.Proposals.Changes.Fingerprint do
  @moduledoc """
  Sets a proposal's words' `content_hash` from the words themselves, the
  fingerprint a proposal made with them carries on the chain.
  """
  use Ash.Resource.Change

  alias Regents.Keyfleet.WalletSteps.VoteSteps

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :text) do
      text when is_binary(text) ->
        Ash.Changeset.force_change_attribute(
          changeset,
          :content_hash,
          VoteSteps.content_hash(text)
        )

      nil ->
        changeset
    end
  end
end
