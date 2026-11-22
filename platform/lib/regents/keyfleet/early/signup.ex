defmodule Regents.Keyfleet.Early.Signup do
  @moduledoc """
  One address on the early-access list, read by the site itself only.
  Nothing here adds one: the action that does comes with the early-access
  page (`SOURCE.json`, `not_brought`).
  """
  use Ash.Resource,
    domain: Regents.Keyfleet.Early,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "early_signups"
    schema("keyfleet_app")
    repo(Regents.Repo)
  end

  actions do
    defaults [:read]
  end

  policies do
    policy action_type(:read) do
      authorize_if actor_attribute_equals(:role, :system)
    end
  end

  identities do
    identity :unique_email, [:email]
  end

  attributes do
    uuid_primary_key :id

    # One @ with something on both sides, a dot in the domain and no spaces. The
    # pattern reads bytes (it has no `u` flag), so its lookahead holds an
    # address to 254 bytes.
    attribute :email, :string,
      allow_nil?: false,
      public?: true,
      constraints: [match: ~r/\A(?=.{1,254}\z)[^@\s]+@[^@\s]+\.[^@\s]+\z/s]

    create_timestamp :inserted_at
  end
end
