defmodule Regents.Keyfleet.Rooms.Mute do
  @moduledoc """
  One person's or agent's choice to stop seeing a key's posts in a fleet's
  rooms: the posts written as the key, by its owner or by any of its shards.

  A mute is personal. It hides the posts only from whoever added it, changes
  nothing for anyone else, and is taken away by unmuting. Muting a key twice
  keeps the one mute. Only a key the fleet has issued is muted, and a muter
  has at most 500 mutes (`Regents.Keyfleet.Rooms.Changes.LimitMutes`).
  """
  use Ash.Resource,
    domain: Regents.Keyfleet.Rooms,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  @max_bigint 9_223_372_036_854_775_807

  postgres do
    table "mutes"
    schema("keyfleet_app")
    repo(Regents.Repo)

    check_constraints do
      check_constraint(:token_id, "mutes_positive_token", check: "token_id > 0")

      check_constraint(:muter, "mutes_muter_shape",
        check: "muter ~ '^(human:[1-9][0-9]*|agent:0x[0-9a-f]{40})$'"
      )
    end
  end

  actions do
    defaults [:read]

    create :mute do
      change Regents.Keyfleet.Agents.Changes.RecordAuthority
      change {RegentAgents.RequirePairing, repo: Regents.Repo}
      accept [:fleet_id, :token_id]
      upsert? true
      upsert_identity :one_per_key
      upsert_fields []
      upsert_condition expr(false)
      return_skipped_upsert? true
      validate Regents.Keyfleet.Graph.Validations.KnownFleet
      # Checked once the muter is known, so anyone else is refused as no muter.
      validate Regents.Keyfleet.Rooms.Validations.IssuedKey, before_action?: true
      change Regents.Keyfleet.Rooms.Changes.SetMuter
      change Regents.Keyfleet.Rooms.Changes.LimitMutes
    end

    destroy :unmute do
      require_atomic? false
      change {RegentAgents.RequirePairing, repo: Regents.Repo}
    end

    # The actor's mutes in a fleet, by key number.
    read :in_fleet do
      argument :fleet_id, :string, allow_nil?: false
      validate Regents.Keyfleet.Graph.Validations.KnownFleet
      filter expr(fleet_id == ^arg(:fleet_id))
      prepare build(sort: [token_id: :asc])
    end

    # The actor's mute of one key, if it has one.
    read :of_key do
      argument :fleet_id, :string, allow_nil?: false
      argument :token_id, :integer, allow_nil?: false
      filter expr(fleet_id == ^arg(:fleet_id) and token_id == ^arg(:token_id))
      get? true
    end
  end

  # Delivered after the transaction commits, as `%Phoenix.Socket.Broadcast{}`
  # with the event "mutes_changed" and `%{fleet_id}`, on
  # `Regents.Keyfleet.Rooms.Muter.topic/1`, so each of the muter's own open pages shows
  # or hides the key's posts again.
  pub_sub do
    module Phoenix.PubSub
    name Regents.PubSub
    prefix "keyfleet:mutes"
    broadcast_type :phoenix_broadcast
    transform &%{fleet_id: &1.data.fleet_id}

    publish :mute, [:muter], event: "mutes_changed"
    publish :unmute, [:muter], event: "mutes_changed"
  end

  # A mute is made, read and undone only by its own muter: a person or an
  # agent signed in. A new mute's muter is set from the actor, and with nobody
  # signed in there is no muter, so the mute is refused.
  policies do
    policy always() do
      authorize_if Regents.Keyfleet.Rooms.Checks.OwnMute
    end
  end

  attributes do
    attribute :acting_agent_wallet, :string, writable?: false
    attribute :beneficiary_privy_user_id, :string, writable?: false, sensitive?: true
    attribute :agent_pairing_id, :uuid, writable?: false

    uuid_primary_key :id

    attribute :muter, :string, allow_nil?: false, public?: true

    attribute :token_id, :integer,
      allow_nil?: false,
      public?: true,
      constraints: [min: 1, max: @max_bigint]

    create_timestamp :inserted_at, public?: true
  end

  relationships do
    belongs_to :fleet, Regents.Keyfleet.Fleets.Fleet do
      attribute_type :string
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :one_per_key, [:muter, :fleet_id, :token_id]
  end
end
