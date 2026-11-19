defmodule RegentPoints.CapUsage do
  @moduledoc false
  use Ash.Resource,
    domain: RegentPoints,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    migrate?(Application.compile_env(:regent_points, :generate_migrations, false))
    table "point_cap_usage"
    schema("regent_points")
    repo(&RegentPoints.repo/2)

    check_constraints do
      check_constraint(:award_count, "cap_nonnegative",
        check: "award_count >= 0 AND points_micro >= 0"
      )
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :account_id, :integer, allow_nil?: false
    attribute :program_id, :string, allow_nil?: false
    attribute :cap_scope, :string, allow_nil?: false
    attribute :window_start, :date, allow_nil?: false
    attribute :window_end, :date
    attribute :award_count, :integer, default: 0, allow_nil?: false, constraints: [min: 0]
    attribute :points_micro, :integer, default: 0, allow_nil?: false, constraints: [min: 0]
  end

  actions do
    read :read do
      primary? true
    end

    create :reserve do
      accept [:account_id, :program_id, :cap_scope, :window_start, :window_end]
      upsert? true
      upsert_identity :allowance
      upsert_fields []
      upsert_condition expr(false)
      return_skipped_upsert? true
    end

    update :consume do
      argument :points, :integer, allow_nil?: false, constraints: [min: 0]
      change atomic_update(:award_count, expr(award_count + 1))
      change atomic_update(:points_micro, expr(points_micro + ^arg(:points)))
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :system) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if expr(account_id == ^actor(:human_account_id))
    end
  end

  identities do
    identity :allowance, [:account_id, :program_id, :cap_scope, :window_start]
  end
end
