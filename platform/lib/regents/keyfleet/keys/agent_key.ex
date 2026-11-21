defmodule Regents.Keyfleet.Keys.AgentKey do
  @moduledoc """
  Which of a person's Keys in a fleet each of their paired agents is on, set
  by the person on the Account page's Your Keys. While the
  person's wallets hold the Key and the agent's pairing lasts, the agent
  writes as that Key there in place of its person's Keys
  (`Regents.Keyfleet.Keys.identity/2`, `Regents.Keyfleet.Keys.held_keys/2`), unless its own
  wallet holds one of the fleet's Keys; an agent on no Key writes as its
  person's Key (`Regents.Keyfleet.Keys.PostingKey`).

  A Key has any number of the person's agents, and an agent one Key in a
  fleet, so it acts as one Key there: one row per agent per fleet. Putting an
  agent on a Key moves it off the Key it was on there.

  The agent is named by its wallet and kept by its pairing's id
  (`RegentAgents.PairedAgent`'s `id`, the `Regents.Account.Actors.Agent`'s
  `pairing_id`), checked against the person's pairings as they stand when it
  is saved (`Regents.Keyfleet.Keys.Changes.PutAgent`), so only an agent paired with
  the account whose wallets hold the Key goes on it. Every reader matches the
  row against the agent's current pairing, so unpairing it, on any Regent
  site, takes it off every Key of that account as the unpair commits, and
  pairing it again starts with none; only the person puts it on one again.

  It is kept with the Key's ownership record as it stood when it was saved
  (`ownership_epoch`), and counts only while the Key stays in that record and
  one of the person's wallets holds it (`Regents.Keyfleet.Keys.placed_on?/3`): a Key
  that changes hands, even between the person's own wallets or back to them,
  has no agents on it. The agents stay paired; each is on no Key in the fleet.

  Putting an agent on a Key, moving it and taking it off (`:assign`,
  `:release`) are the signed-in person's alone (Sean, 12 November 2026): no
  agent places an agent, itself included. Each write tells the fleet's pages
  which Keys it changed (`Regents.Keyfleet.Keys.Changes.TellKeysChanged`). The person
  and their paired agents read only their own person's rows; which Key any
  agent is on is read by trusted code alone, through
  `Regents.Keyfleet.Keys.assigned_keys/3`.
  """
  use Ash.Resource,
    domain: Regents.Keyfleet.Keys,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  @max_bigint 9_223_372_036_854_775_807

  postgres do
    table "agent_keys"
    schema("keyfleet_app")
    repo(Regents.Repo)

    custom_indexes do
      index([:human_account_id, :fleet_id], name: "agent_keys_person_index")
    end

    check_constraints do
      check_constraint(:token_id, "agent_keys_positive_token", check: "token_id > 0")

      check_constraint(:ownership_epoch, "agent_keys_positive_epoch",
        check: "ownership_epoch >= 1"
      )
    end
  end

  actions do
    # Puts the agent `agent_wallet` names on the Key, moving it off the Key it
    # was on in the fleet.
    create :assign do
      accept [:fleet_id, :token_id]

      argument :agent_wallet, :string,
        allow_nil?: false,
        constraints: [match: ~r/\A0x[0-9a-fA-F]{40}\z/]

      change set_attribute(:human_account_id, actor(:human_account_id))
      upsert? true
      upsert_identity :one_key_per_agent
      upsert_fields [:token_id, :ownership_epoch, :updated_at]
      validate Regents.Keyfleet.Graph.Validations.KnownFleet
      change Regents.Keyfleet.Keys.Changes.PutAgent
      change Regents.Keyfleet.Keys.Changes.TellKeysChanged
    end

    # The person takes one of their agents off the Key it is on.
    destroy :release do
      require_atomic? false
      change Regents.Keyfleet.Keys.Changes.TellKeysChanged
    end

    read :read do
      primary? true
    end

    # Every Key the person has put one of their agents on, every fleet.
    read :of_person do
      filter expr(human_account_id == ^actor(:human_account_id))
    end

    # The Keys the agents with these wallets are on in a fleet, each by its
    # wallet's current pairing, with that wallet (`:agent_wallet`). Whether
    # the person still holds each Key is `Regents.Keyfleet.Keys.assigned_keys/3`'s,
    # the one reader.
    read :of_agents do
      argument :fleet_id, :string, allow_nil?: false
      argument :wallets, {:array, :string}, allow_nil?: false

      filter expr(
               fleet_id == ^arg(:fleet_id) and
                 fragment(
                   "? IN (SELECT pairing.id FROM regent_agents.paired_agents AS pairing WHERE pairing.wallet = ANY(?))",
                   paired_agent_id,
                   ^arg(:wallets)
                 )
             )

      prepare build(load: [:agent_wallet])
    end
  end

  # A person, and an agent paired with a person who has signed in here, carry
  # the person's account (`Regents.Account.Actors.Agent`'s `human_account_id`);
  # nobody else does.
  policies do
    # Only the signed-in person places, moves or takes off an agent on a Key.
    policy action(:assign) do
      forbid_unless actor_attribute_equals(:role, :human)
      authorize_if expr(not is_nil(^actor(:human_account_id)))
    end

    policy action(:release) do
      forbid_unless actor_attribute_equals(:role, :human)
      authorize_if expr(human_account_id == ^actor(:human_account_id))
    end

    policy action(:of_person) do
      authorize_if expr(not is_nil(^actor(:human_account_id)))
    end

    policy action(:read) do
      authorize_if expr(human_account_id == ^actor(:human_account_id))
    end

    # Which Key each agent acts as is public, but pairings are for trusted
    # code only.
    policy action(:of_agents) do
      authorize_if actor_attribute_equals(:role, :system)
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :human_account_id, :integer, allow_nil?: false, public?: true

    attribute :token_id, :integer,
      allow_nil?: false,
      public?: true,
      constraints: [min: 1, max: @max_bigint]

    # The agent's pairing (`RegentAgents.PairedAgent`).
    attribute :paired_agent_id, :uuid, allow_nil?: false, public?: true

    # The Key's ownership record (`Regents.Keyfleet.Keys.KeyAttachment`) when the row
    # was saved; the row counts only while the Key is still in it.
    attribute :ownership_epoch, :integer,
      allow_nil?: false,
      public?: true,
      constraints: [min: 1, max: @max_bigint]

    update_timestamp :updated_at, public?: true
  end

  calculations do
    # The wallet of the agent on the Key while its pairing lasts, nil once it
    # is unpaired. Read in SQL, since pairings are for trusted code only.
    calculate :agent_wallet,
              :string,
              expr(
                fragment(
                  "(SELECT pairing.wallet FROM regent_agents.paired_agents AS pairing WHERE pairing.id = ?)",
                  paired_agent_id
                )
              )
  end

  relationships do
    belongs_to :fleet, Regents.Keyfleet.Fleets.Fleet do
      attribute_type :string
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :one_key_per_agent, [:paired_agent_id, :fleet_id]
  end
end
