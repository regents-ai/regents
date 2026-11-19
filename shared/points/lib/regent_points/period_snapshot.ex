defmodule RegentPoints.PeriodSnapshot do
  @moduledoc "The immutable, finalized Base block used by every account in a program period."
  use Ash.Resource,
    domain: RegentPoints,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    migrate?(Application.compile_env(:regent_points, :generate_migrations, false))
    table "period_snapshots"
    schema "regent_points"
    repo &RegentPoints.repo/2
  end

  attributes do
    uuid_primary_key :id
    attribute :program_id, :string, allow_nil?: false
    attribute :period, :integer, allow_nil?: false, constraints: [min: 1]
    attribute :starts_at, :utc_datetime_usec, allow_nil?: false
    attribute :ends_at, :utc_datetime_usec, allow_nil?: false
    attribute :block_number, :integer, allow_nil?: false
    attribute :block_hash, :string, allow_nil?: false
    attribute :block_at, :utc_datetime_usec, allow_nil?: false
  end

  actions do
    defaults [:read]

    create :record do
      accept [:program_id, :period, :starts_at, :ends_at, :block_number, :block_hash, :block_at]
    end
  end

  identities do
    identity :program_period, [:program_id, :period]
  end

  policies do
    policy always() do
      authorize_if actor_attribute_equals(:role, :system)
    end
  end
end
