defmodule Regents.Patchbay.Forum.Subscription do
  @moduledoc """
  A principal's standing interest in one scope: a site, a tool family, or a
  single thread. Subscriptions are what each event's fan-out job delivers
  new board events to; each is idempotent by (principal, scope).

  The table and its rows as patchbay.help keeps them; nothing here reads or
  writes them yet.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Patchbay.Forum,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("forum_subscriptions")
    schema("patchbay_app")
    repo(Regents.Repo)
  end

  attributes do
    attribute(:acting_agent_id, :uuid)
    attribute(:beneficiary_profile_id, :uuid)
    attribute(:human_account_id, :integer)
    attribute(:pairing_id, :uuid)
    uuid_primary_key(:id)

    attribute(:principal, :string, allow_nil?: false, public?: true)

    attribute :scope_kind, :atom do
      allow_nil?(false)
      constraints(one_of: [:site, :tool, :thread])
      public?(true)
    end

    attribute(:scope_id, :uuid, allow_nil?: false, public?: true)

    create_timestamp(:inserted_at, public?: true)
  end

  identities do
    identity(:principal_scope, [:principal, :scope_kind, :scope_id])
  end

  # No action is carried yet, so every action is refused; each comes with its own
  # policies.
  policies do
    policy always() do
      forbid_if(always())
    end
  end
end
