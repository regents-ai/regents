defmodule Regents.Autolaunch.XConnection do
  @moduledoc """
  A verified, role-scoped X identity owned by one Human account.

  OAuth credentials never live here. A row keeps only the short-lived PKCE
  attempt needed to finish one browser popup and the public identity returned
  by X after that attempt succeeds.

  The table and its rows as autolaunch.sh keeps them; nothing here reads or
  writes them yet.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Autolaunch,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "x_connections"
    schema("autolaunch_app")
    repo(Regents.Repo)

    references do
      reference(:human_account, on_delete: :delete)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :role, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:profile, :company]
    end

    attribute :x_user_id, :string do
      public? true
      constraints max_length: 64, trim?: true
    end

    attribute :username, :string do
      public? true
      constraints max_length: 64, trim?: true
    end

    attribute :display_name, :string do
      public? true
      constraints max_length: 100, trim?: true
    end

    attribute :avatar_url, :string do
      public? true
      constraints max_length: 500, trim?: true
    end

    attribute :verified_at, :utc_datetime_usec do
      public? true
    end

    attribute :attempt_state, :string do
      sensitive? true
      constraints max_length: 512
    end

    attribute :attempt_verifier, :string do
      sensitive? true
      constraints max_length: 512
    end

    attribute :attempt_generation, :uuid do
      sensitive? true
    end

    attribute :attempt_expires_at, :utc_datetime_usec do
      sensitive? true
    end

    attribute :intent_sequence, :integer do
      sensitive? true
    end

    attribute :intent_generation, :uuid do
      sensitive? true
    end

    timestamps()
  end

  relationships do
    belongs_to :human_account, Regents.Account.Accounts.HumanAccount do
      allow_nil? false
      attribute_type :integer
    end
  end

  identities do
    identity :one_role_per_human, [:human_account_id, :role]
  end

  # No action is carried yet, so every action is refused; each comes with its own
  # policies.
  policies do
    policy always() do
      forbid_if always()
    end
  end
end
