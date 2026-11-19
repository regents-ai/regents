defmodule RegentPoints.Rejection do
  @moduledoc "Permanent, private audit of rejected source references; no queue or retry state."
  use Ash.Resource,
    domain: RegentPoints,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    migrate?(Application.compile_env(:regent_points, :generate_migrations, false))
    repo &RegentPoints.repo/2
    table "source_rejections"
    schema "regent_points"
  end

  attributes do
    uuid_primary_key :id
    attribute :source, :map, allow_nil?: false, sensitive?: true
    attribute :reason_code, :string, allow_nil?: false
    attribute :rejection_key, :string, allow_nil?: false
    create_timestamp :recorded_at
  end

  actions do
    defaults [:read]

    create :record do
      accept [:source, :reason_code, :rejection_key]
      upsert? true
      upsert_identity :rejected_source
      upsert_fields []
      upsert_condition expr(false)
      return_skipped_upsert? true
    end
  end

  policies do
    policy always() do
      authorize_if actor_attribute_equals(:role, :system)
    end
  end

  identities do
    identity :rejected_source, [:rejection_key]
  end
end
