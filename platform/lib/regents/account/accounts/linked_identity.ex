defmodule Regents.Account.Accounts.LinkedIdentity do
  @moduledoc """
  A social account Privy verified for one human account, one per provider.
  Several human accounts may link the same social account of a shared provider
  (`@shared_providers`); any other provider's social account is linked to one
  human account at a time.

  `inserted_at` is when this subject was linked to this account: a later
  sign-in with the same subject leaves it, and linking a different subject for
  the provider resets it. `verified_at` is Privy's newest check of the link.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Account.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  # The providers whose social accounts several human accounts may link at once,
  # and the one place that choice is made. Every other provider's subject is held
  # by one account, which the database keeps to (`:unique_subject_per_provider`).
  @shared_providers [:x]

  actions do
    # A refresh finds its row through the primary read.
    read :read do
      primary? true
    end

    create :upsert_verified do
      accept []

      argument :provider, :atom,
        allow_nil?: false,
        constraints: [one_of: [:x, :github, :farcaster, :ens, :world]]

      argument :subject, :string, allow_nil?: false
      argument :username, :string
      argument :display_name, :string
      argument :verified_at, :utc_datetime_usec, allow_nil?: false
      argument :metadata, :map, allow_nil?: false
      argument :human_account_id, :integer, allow_nil?: false

      change set_attribute(:provider, arg(:provider))
      change set_attribute(:subject, arg(:subject))
      change set_attribute(:username, arg(:username))
      change set_attribute(:display_name, arg(:display_name))
      change set_attribute(:verified_at, arg(:verified_at))
      change set_attribute(:metadata, arg(:metadata))
      change set_attribute(:human_account_id, arg(:human_account_id))

      upsert? true
      upsert_identity :unique_provider_per_account
      # Reached only for a subject new to the account: a first link for the
      # provider, or one that replaces the account's earlier subject, so
      # `inserted_at` is always when this subject was linked.
      upsert_fields [:subject, :username, :display_name, :verified_at, :metadata, :inserted_at]

      emit Regents.Account.Accounts.Signals, :social_linked
    end

    # A sign-in whose subject is still linked to the account. The domain finds the
    # row by provider, subject and account in the same statement that updates it.
    update :refresh_verified do
      accept [:username, :display_name, :verified_at, :metadata]
    end

    read :read_mine do
      filter expr(human_account_id == ^actor(:human_account_id))
      prepare build(sort: [provider: :asc])
    end

    read :for_account do
      argument :human_account_id, :integer, allow_nil?: false
      filter expr(human_account_id == ^arg(:human_account_id))
      prepare build(sort: [provider: :asc])
    end

    # What a product shows beside several people at once: their links by account,
    # with the public fields alone, never the subject or Privy's metadata. At most
    # 100 accounts a read.
    read :for_accounts do
      argument :human_account_ids, {:array, :integer},
        allow_nil?: false,
        constraints: [max_length: 100]

      filter expr(human_account_id in ^arg(:human_account_ids))

      prepare build(
                select: [:human_account_id, :provider, :username, :display_name, :verified_at],
                sort: [human_account_id: :asc, provider: :asc]
              )
    end

    # Of the accounts that hold one social account, the link made first: the one
    # its Points answer for (`Regents.Account.Points.LinkedSocial`), so a later link by
    # another account moves nothing.
    read :first_link do
      get? true
      argument :provider, :atom, allow_nil?: false
      argument :subject, :string, allow_nil?: false
      filter expr(provider == ^arg(:provider) and subject == ^arg(:subject))
      prepare build(sort: [inserted_at: :asc, human_account_id: :asc], limit: 1)
    end

    # Each account's link to one provider made before a moment, such as the time the
    # Points start run reads them, by provider, subject and account alone, in
    # `:first_link`'s order.
    read :linked_before do
      argument :provider, :atom, allow_nil?: false
      argument :at, :utc_datetime_usec, allow_nil?: false
      filter expr(provider == ^arg(:provider) and inserted_at < ^arg(:at))

      prepare build(
                select: [:provider, :subject, :human_account_id],
                sort: [inserted_at: :asc, human_account_id: :asc]
              )
    end

    destroy :remove_verified do
      accept []
      require_atomic? false
    end
  end

  policies do
    policy action([
             :read,
             :upsert_verified,
             :refresh_verified,
             :for_account,
             :for_accounts,
             :first_link,
             :linked_before,
             :remove_verified
           ]) do
      authorize_if actor_attribute_equals(:__struct__, Regents.Account.Actors.System)
    end

    policy action(:read_mine) do
      authorize_if Regents.Account.Accounts.Checks.HumanActor
    end
  end

  # Open tabs across the site (Autolaunch create forms, bid share panels, and
  # other /account/connections tabs) follow linked-identity changes for the
  # signed-in account (`Regents.Account.Accounts.subscribe_linked_identities/1`).
  pub_sub do
    module Phoenix.PubSub
    name Regents.PubSub

    transform fn notification ->
      {:linked_identities_changed, notification.data.human_account_id, notification.data.provider}
    end

    publish :upsert_verified, ["account_linked_identities", :human_account_id]
    publish :refresh_verified, ["account_linked_identities", :human_account_id]
    publish :remove_verified, ["account_linked_identities", :human_account_id]
  end

  identities do
    # One row per account and provider, so one per account and subject, shared
    # or not: sign-ins of one account at once meet in `:upsert_verified`, whose
    # conflict target this is.
    identity :unique_provider_per_account, [:provider, :human_account_id]

    # A sign-in reports the subject error as a social account another account
    # holds (`Regents.Account.Accounts.VerifiedSession`).
    identity :unique_subject_per_provider, [:provider, :subject] do
      where expr(provider not in ^@shared_providers)
      field_names [:subject]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :provider, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:x, :github, :farcaster, :ens, :world]
    end

    attribute :subject, :string, allow_nil?: false
    attribute :username, :string, public?: true
    attribute :display_name, :string, public?: true
    attribute :verified_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :metadata, :map, allow_nil?: false, default: %{}
    timestamps()
  end

  relationships do
    belongs_to :human_account, Regents.Account.Accounts.HumanAccount do
      allow_nil? false
      attribute_type :integer
    end
  end

  postgres do
    table "linked_identities"
    repo(Regents.Repo)

    identity_wheres_to_sql(
      unique_subject_per_provider:
        "provider NOT IN (#{Enum.map_join(@shared_providers, ", ", &"'#{&1}'")})"
    )

    custom_indexes do
      # Points reads the links to one social account by its provider and subject,
      # shared or not. Built in the same short transaction as the subject rule.
      index([:provider, :subject])
    end
  end
end
