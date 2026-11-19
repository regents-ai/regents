defmodule RegentPoints.Account do
  @moduledoc """
  One account in the shared Points ledger. `balance_micro` is its total: every
  entry plus every period bonus. Each entry and bonus write moves it inside the
  write's own transaction (`RegentPoints.FollowBalance`), so the board and a
  reader's place read it from one index instead of summing the ledger.
  """
  use Ash.Resource,
    domain: RegentPoints,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    migrate?(Application.compile_env(:regent_points, :generate_migrations, false))
    table "accounts"
    schema("regent_points")
    repo(&RegentPoints.repo/2)

    custom_indexes do
      # The board's order, highest total first and then the lowest account id
      # (RegentPoints.Leaderboard), and the count of accounts above a reader.
      index([{:desc, :balance_micro}, :id], concurrently: true)
    end
  end

  attributes do
    attribute :id, :integer, primary_key?: true, allow_nil?: false
    attribute :balance_micro, :integer, allow_nil?: false, default: 0
    create_timestamp :inserted_at
  end

  actions do
    read :read do
      primary? true
    end

    create :open do
      accept [:id]
      upsert? true
      upsert_identity :canonical_account
      upsert_fields []
      upsert_condition expr(false)
      return_skipped_upsert? true
    end

    # Run only by RegentPoints.FollowBalance, in the transaction of the entry or
    # bonus write it follows; the sum is taken in the database.
    update :add_to_balance do
      argument :points_micro, :integer, allow_nil?: false
      change atomic_update(:balance_micro, expr(balance_micro + ^arg(:points_micro)))
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :system) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if expr(id == ^actor(:human_account_id))
    end
  end

  identities do
    identity :canonical_account, [:id]
  end

  relationships do
    belongs_to :human_account, RegentPoints.HumanAccount do
      source_attribute :id
      define_attribute? false
      attribute_type :integer
      allow_nil? false
    end

    has_many :entries, RegentPoints.Entry, destination_attribute: :account_id
    has_many :period_bonuses, RegentPoints.PeriodBonus, destination_attribute: :account_id
  end
end
