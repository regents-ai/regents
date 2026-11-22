defmodule Regents.Keyfleet.Agents.Changes.RecordAuthority do
  @moduledoc "Retain the verified agent, beneficiary and episode on a saved outcome."
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, %{actor: %Regents.Account.Actors.Agent{} = actor}) do
    Ash.Changeset.force_change_attributes(changeset, %{
      acting_agent_wallet: actor.wallet_address,
      beneficiary_privy_user_id: actor.privy_user_id,
      agent_pairing_id: actor.pairing_id
    })
  end

  def change(changeset, _opts, _context), do: changeset
end
