defmodule Regents.Keyfleet.Keys.PostingKey do
  @moduledoc """
  The Key a person writes as in one fleet, chosen on the Account page or by
  an agent paired with them (`Regents.Keyfleet.Keys.Checks.ActsForPerson`). While
  their wallets hold it, everything they write in the fleet is written as it,
  and so is everything their agents write there for them
  (`Regents.Keyfleet.Keys.identity/2`). A person who has chosen none, or whose chosen
  Key has since left their wallets, writes as the first Key their wallets hold.

  Only its own person, or their agent, sets it, and only a Key the person's
  wallets hold now is chosen (`Regents.Keyfleet.Keys.Validations.HeldByPerson`). Choosing again
  replaces the choice, and the fleet hears the Key chosen
  (`Regents.Keyfleet.Keys.Changes.TellKeysChanged`). The choice is no secret: everything
  the person writes shows it, and so do the city's ships (`Regents.Keyfleet.Keys.faces/2`).
  """
  use Ash.Resource,
    domain: Regents.Keyfleet.Keys,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  @max_bigint 9_223_372_036_854_775_807

  postgres do
    table "posting_keys"
    schema("keyfleet_app")
    repo(Regents.Repo)

    check_constraints do
      check_constraint(:token_id, "posting_keys_positive_token", check: "token_id > 0")
    end
  end

  actions do
    create :choose do
      accept [:fleet_id, :token_id]
      change set_attribute(:human_account_id, actor(:human_account_id))
      change {RegentAgents.RequirePairing, repo: Regents.Repo}
      upsert? true
      upsert_identity :one_per_fleet
      upsert_fields [:token_id, :updated_at]
      validate Regents.Keyfleet.Graph.Validations.KnownFleet
      # Checked once the policy has let a person through.
      validate Regents.Keyfleet.Keys.Validations.HeldByPerson, before_action?: true
      change Regents.Keyfleet.Keys.Changes.TellKeysChanged
    end

    # The person's own choice in a fleet, if they have made one.
    read :in_fleet do
      argument :fleet_id, :string, allow_nil?: false

      filter expr(fleet_id == ^arg(:fleet_id) and human_account_id == ^actor(:human_account_id))

      get? true
    end

    # The choices of several people in a fleet, for the city's ships, which
    # show the Key each holder writes as.
    read :of_accounts do
      argument :fleet_id, :string, allow_nil?: false
      argument :human_account_ids, {:array, :integer}, allow_nil?: false

      filter expr(fleet_id == ^arg(:fleet_id) and human_account_id in ^arg(:human_account_ids))
    end
  end

  policies do
    policy action([:choose, :in_fleet]) do
      authorize_if Regents.Keyfleet.Keys.Checks.ActsForPerson
    end

    policy action(:of_accounts) do
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

    update_timestamp :updated_at, public?: true
  end

  relationships do
    belongs_to :fleet, Regents.Keyfleet.Fleets.Fleet do
      attribute_type :string
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :one_per_fleet, [:human_account_id, :fleet_id]
  end
end
