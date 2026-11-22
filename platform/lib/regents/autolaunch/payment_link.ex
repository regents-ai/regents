defmodule Regents.Autolaunch.PaymentLink do
  @moduledoc """
  One payment link of a launched subject: the wallet it pays and its label.

  The table and its rows as autolaunch.sh keeps them; nothing here reads or
  writes them yet.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Autolaunch,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "payment_links"
    schema("autolaunch_app")
    repo(Regents.Repo)

    custom_indexes do
      index([:subject_id])
    end
  end

  attributes do
    uuid_primary_key :id, public?: false

    attribute :receiver_address, :string do
      allow_nil? false
      public? true
      constraints min_length: 42, max_length: 42, match: ~r/\A0x[0-9a-f]{40}\z/
    end

    attribute :label, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 96, trim?: true
    end

    create_timestamp :created_at
  end

  relationships do
    belongs_to :subject, Regents.Autolaunch.Subject do
      allow_nil? false
    end
  end

  identities do
    identity :unique_receiver_address, [:receiver_address]
  end

  # No action is carried yet, so every action is refused; each comes with its own
  # policies.
  policies do
    policy always() do
      forbid_if always()
    end
  end
end
