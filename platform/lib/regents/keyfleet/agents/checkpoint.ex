defmodule Regents.Keyfleet.Agents.Checkpoint do
  @moduledoc """
  Where an agent left off in one fleet, kept here so the agent, or a fresh
  run of it on any machine, picks up from there: `state` is the agent's own
  JSON object, such as the task it works, that task's version, its cursors
  and the runs it waits on. Only the agent's own wallet reads or saves it.

  Each save names the `revision` it read, 0 for the first, and makes the
  next one, so two runs of one agent never overwrite each other unseen: a
  save from any other revision changes nothing (`Regents.Keyfleet.Agents.save_checkpoint/4`).
  """
  use Ash.Resource,
    domain: Regents.Keyfleet.Agents,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "agent_checkpoints"
    schema("keyfleet_app")
    repo(Regents.Repo)

    check_constraints do
      check_constraint(:revision, "agent_checkpoints_revision", check: "revision >= 1")
    end
  end

  actions do
    # The agent's own checkpoint in one fleet.
    read :mine do
      get? true
      argument :fleet_id, :string, allow_nil?: false
      filter expr(wallet == ^actor(:wallet_address) and fleet_id == ^arg(:fleet_id))
    end

    # The first save, as revision 1.
    create :start do
      accept [:fleet_id, :state]
      change {RegentAgents.RequirePairing, repo: Regents.Repo}
      change set_attribute(:wallet, actor(:wallet_address))
      change set_attribute(:revision, 1)
    end

    # Every later save, as the next revision, made only from the revision it
    # read; the pairing lock it takes keeps it from being one statement.
    update :save do
      require_atomic? false
      accept [:state]
      change {RegentAgents.RequirePairing, repo: Regents.Repo}
      change optimistic_lock(:revision)
    end
  end

  policies do
    policy action_type([:read, :create]) do
      authorize_if actor_attribute_equals(:role, :agent)
    end

    policy action(:save) do
      authorize_if expr(wallet == ^actor(:wallet_address))
    end
  end

  attributes do
    attribute :wallet, :string, primary_key?: true, allow_nil?: false, public?: true
    attribute :fleet_id, :string, primary_key?: true, allow_nil?: false, public?: true
    attribute :revision, :integer, allow_nil?: false, public?: true, constraints: [min: 1]
    attribute :state, :map, allow_nil?: false, public?: true
    update_timestamp :updated_at, public?: true
  end
end
