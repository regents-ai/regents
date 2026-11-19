defmodule RegentPoints.WalletCoverage do
  @moduledoc "The migration's capture boundary. Earlier program starts cannot be reconstructed."
  use Ash.Resource,
    domain: RegentPoints,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    migrate?(Application.compile_env(:regent_points, :generate_migrations, false))
    table "wallet_coverage"
    schema "regent_points"
    repo &RegentPoints.repo/2
  end

  attributes do
    attribute :id, :integer, primary_key?: true, allow_nil?: false
    attribute :starts_at, :utc_datetime_usec, allow_nil?: false
  end

  actions do
    defaults [:read]
  end

  policies do
    policy action_type(:read) do
      authorize_if actor_attribute_equals(:role, :system)
    end
  end
end
