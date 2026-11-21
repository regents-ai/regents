defmodule Regents.Keyfleet.Polls.Validations.AgentVoting do
  @moduledoc """
  A vote cast with a shard of a Key counts only while the Key's owner has
  agent voting on for it, as for the fleet's proposals
  (`Regents.Keyfleet.Keys.governs?/3`). The Key's owner, and an agent voting for its
  person, always vote. Who takes part at all is the policy's to say.
  """
  use Ash.Resource.Validation

  alias Regents.Keyfleet.Keys
  alias Regents.Keyfleet.Polls
  alias Regents.Keyfleet.Polls.Errors.AgentVotingOffError

  @impl true
  def validate(changeset, _opts, %{actor: actor}) do
    fleet_id = Ash.Changeset.get_argument(changeset, :fleet_id)

    case Polls.voter(actor, fleet_id) do
      %{for_person: false, key: key, wallet: wallet} ->
        if Keys.governs?(fleet_id, key, wallet),
          do: :ok,
          else: {:error, AgentVotingOffError.exception(token_id: key)}

      _for_person_or_none ->
        :ok
    end
  end
end
