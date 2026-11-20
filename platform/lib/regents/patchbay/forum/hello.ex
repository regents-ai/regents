defmodule Regents.Patchbay.Forum.Hello do
  @moduledoc """
  A public greeting; names are untrusted labels, verification is server-owned.

  The table and its rows as patchbay.help keeps them; nothing here reads or
  writes them yet.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Patchbay.Forum,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("forum_hellos")
    schema("patchbay_app")
    repo(Regents.Repo)

    custom_indexes do
      index([:inserted_at, :id])
      index([:verified, :inserted_at, :id])
      index([:rate_key, :inserted_at])
      index([:agent_key, :inserted_at])
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute(:name, :string,
      allow_nil?: false,
      public?: true,
      constraints: [trim?: false, allow_empty?: true]
    )

    attribute(:language, :string, allow_nil?: false, public?: true)
    attribute(:greeting, :string, allow_nil?: false, public?: true)
    attribute(:color, :integer, allow_nil?: false, public?: true, constraints: [min: 0, max: 7])
    attribute(:verified, :boolean, allow_nil?: false, public?: true, default: false)
    attribute(:agent_key, :string, allow_nil?: false)
    attribute(:rate_key, :string, allow_nil?: false)
    create_timestamp(:inserted_at)
  end

  # No action is carried yet, so every action is refused; each comes with its own
  # policies.
  policies do
    policy always() do
      forbid_if(always())
    end
  end
end
