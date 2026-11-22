defmodule Regents.Keyfleet.Notebooks.Handoff do
  @moduledoc """
  A link that opens a fleet's notebooks for one person, once, under the
  Keyfleet sign-in it was made in (`session_authority_id`): the notebook
  sign-in it sets lasts only as long as that one.

  Only the code's SHA-256 is kept. A link is spent by the one statement that
  checks it (`Regents.Keyfleet.Notebooks.redeem/2`), and links a day past their time
  are cleared by `Regents.Keyfleet.Notebooks.Reconcile`.
  """
  use Ash.Resource,
    domain: Regents.Keyfleet.Notebooks,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "notebook_handoffs"
    schema("keyfleet_app")
    repo(Regents.Repo)
  end

  actions do
    create :issue do
      accept [:code_hash, :fleet_id, :human_account_id, :session_authority_id, :expires_at]
    end

    read :redeemable do
      argument :code_hash, :binary, allow_nil?: false
      argument :fleet_id, :string, allow_nil?: false

      filter expr(
               code_hash == ^arg(:code_hash) and fleet_id == ^arg(:fleet_id) and
                 is_nil(used_at) and expires_at > now()
             )
    end

    update :redeem do
      accept []
      change atomic_update(:used_at, expr(now()))
    end

    read :expired do
      filter expr(expires_at < ago(1, :day))
    end

    destroy :clear
  end

  policies do
    policy always() do
      authorize_if actor_attribute_equals(:role, :system)
    end
  end

  identities do
    identity :unique_code_hash, [:code_hash]
  end

  attributes do
    uuid_primary_key :id
    attribute :code_hash, :binary, allow_nil?: false, sensitive?: true
    attribute :fleet_id, :string, allow_nil?: false
    attribute :human_account_id, :integer, allow_nil?: false
    attribute :session_authority_id, :uuid, allow_nil?: false
    attribute :expires_at, :utc_datetime_usec, allow_nil?: false
    attribute :used_at, :utc_datetime_usec
    create_timestamp :inserted_at
  end
end
