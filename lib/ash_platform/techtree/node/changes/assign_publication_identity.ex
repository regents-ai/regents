defmodule AshPlatform.Techtree.Node.Changes.AssignPublicationIdentity do
  @moduledoc false
  use Ash.Resource.Change

  alias AshPlatform.AgentAuth.AgentIdentity

  @impl true
  def change(changeset, _opts, %{actor: %AgentIdentity{} = actor}) do
    changeset
    |> Ash.Changeset.force_change_attribute(:contributor_id, actor.agent_id)
    |> Ash.Changeset.force_change_attribute(:publisher_agent_id, actor.agent_id)
    |> Ash.Changeset.force_change_attribute(:publisher_registry_address, actor.registry_address)
    |> Ash.Changeset.force_change_attribute(:publisher_token_id, actor.token_id)
    |> Ash.Changeset.force_change_attribute(:publisher_wallet, actor.wallet)
    |> Ash.Changeset.force_change_attribute(:publisher_chain_id, actor.chain_id)
    |> Ash.Changeset.force_change_attribute(:publisher_regent_id, actor.regent_id)
  end

  def change(changeset, _opts, _context), do: changeset
end
