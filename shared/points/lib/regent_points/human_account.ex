defmodule RegentPoints.HumanAccount do
  @moduledoc "Read-only foreign-key target in Regent's canonical account schema. The host owns account lookup and verification."
  use Ash.Resource,
    domain: RegentPoints,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    repo &RegentPoints.repo/2
    table "platform_human_users"
    schema "regent_names"
    migrate? false
  end

  attributes do
    integer_primary_key :id
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
