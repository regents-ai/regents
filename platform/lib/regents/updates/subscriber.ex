defmodule Regents.Updates.Subscriber do
  @moduledoc """
  One email address left for updates, kept in lowercase so each address is on
  the list once, with the page it was left on (`source`) and when. Leaving an
  address already on the list answers the same as a new one, so nobody learns
  whether it was there. Each visitor's network leaves a few a minute
  (`LimitTries`). Nothing reads the list through Ash.
  """

  use Ash.Resource,
    domain: Regents.Updates,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Regents.Updates.Subscriber.LimitTries

  postgres do
    table "update_subscribers"
    repo(Regents.Repo)
  end

  attributes do
    uuid_primary_key :id
    attribute :address, :string, allow_nil?: false, constraints: [max_length: 254]
    # The page the address was left on.
    attribute :source, :atom, allow_nil?: false, public?: true, constraints: [one_of: [:cloak]]
    create_timestamp :inserted_at
  end

  identities do
    identity :address, [:address]
  end

  actions do
    # The first time an address is left is the one kept: a repeat changes nothing.
    create :subscribe do
      accept [:source]
      upsert? true
      upsert_identity :address
      upsert_fields []

      argument :address, :ci_string,
        allow_nil?: false,
        constraints: [casing: :lower, max_length: 254]

      validate match(:address, ~r/\A[^@\s]+@[^@\s.]+(\.[^@\s.]+)+\z/),
        message: "Enter a valid email address."

      change set_attribute(:address, arg(:address))
      change LimitTries
    end
  end

  policies do
    # Anyone, signed in or not, may leave an address.
    policy action(:subscribe) do
      authorize_if always()
    end
  end
end
