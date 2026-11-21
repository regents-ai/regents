defmodule Regents.Keyfleet.Proposals.Changes.FindProposal do
  @moduledoc """
  Points a vote or execution at the recorded proposal its log names by number.
  The reader records a vote or execution only once its proposal is recorded.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    %{id: proposal_id} =
      Regents.Keyfleet.Proposals.get_proposal!(
        Ash.Changeset.get_attribute(changeset, :fleet_id),
        Ash.Changeset.get_argument(changeset, :proposal_number)
      )

    Ash.Changeset.force_change_attribute(changeset, :proposal_id, proposal_id)
  end
end
