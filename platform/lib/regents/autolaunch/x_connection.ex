defmodule Regents.Autolaunch.XConnection do
  @moduledoc """
  A verified, role-scoped X identity owned by one Human account.

  OAuth credentials never live here. A row keeps only the short-lived PKCE
  attempt needed to finish one browser popup and the public identity returned
  by X after that attempt succeeds.

  The table and its rows as autolaunch.sh keeps them. Autolaunch's lists read
  a creator's verified names; nothing here writes them yet.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Autolaunch,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    primary_read_warning?: false

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

  actions do
    read :related_public do
      primary? true

      prepare build(
                select: [
                  :id,
                  :role,
                  :x_user_id,
                  :username,
                  :display_name,
                  :avatar_url,
                  :verified_at,
                  :human_account_id
                ]
              )
    end

    read :public_for_humans do
      # One page of a list at most (the lists' largest page is 100).
      argument :human_account_ids, {:array, :integer},
        allow_nil?: false,
        constraints: [max_length: 100]

      filter expr(human_account_id in ^arg(:human_account_ids) and not is_nil(verified_at))

      prepare build(
                sort: [human_account_id: :asc, role: :asc],
                select: [
                  :id,
                  :role,
                  :x_user_id,
                  :username,
                  :display_name,
                  :avatar_url,
                  :verified_at,
                  :human_account_id
                ]
              )
    end
  end

  # Only the public reads are carried; any other action is refused until it
  # comes with its own policy.
  policies do
    policy action(:related_public) do
      authorize_if expr(not is_nil(verified_at))
    end

    policy action(:public_for_humans) do
      authorize_if always()
    end
  end
end
