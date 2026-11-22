defmodule Regents.Account.Accounts.PublicLink do
  @moduledoc """
  A verified social link that names a username, with its public fields alone:
  the account (`human_account_id`), the provider, the username and the display
  name. It reads the view `regents_app.public_links` over the table of
  `Regents.Account.Accounts.LinkedIdentity`, where every row is a link Privy
  verified, keeping the links with a username. For the same accounts it answers
  what `Regents.Account.Accounts.list_linked_identities_for_accounts/2` answers,
  less the links without a username, and never the subject, Privy's metadata or
  a time. An account links one social account a provider, so `human_account_id`
  and `provider` together name a row.

  Any product's resource may relate to it by account id and filter, search, sort
  and aggregate through it in SQL. Its read admits everyone, signed out
  included: these are the fields a product shows beside a person on its public
  pages.
  """

  use Ash.Resource,
    domain: Regents.Account.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "public_links"
    repo(Regents.Repo)
    migrate?(false)
  end

  attributes do
    attribute :human_account_id, :integer, primary_key?: true, allow_nil?: false, public?: true

    # `LinkedIdentity`'s providers.
    attribute :provider, :atom do
      primary_key? true
      allow_nil? false
      public? true
      constraints one_of: [:x, :github, :farcaster, :ens, :world]
    end

    attribute :username, :string, allow_nil?: false, public?: true
    attribute :display_name, :string, public?: true
  end

  actions do
    defaults [:read]

    # The links of up to a hundred accounts, for a list that shows each
    # member's: the provider and username only, in a steady order.
    read :for_accounts do
      argument :account_ids, {:array, :integer}, allow_nil?: false, constraints: [max_length: 100]
      filter expr(human_account_id in ^arg(:account_ids))
      prepare build(select: [:username], sort: [human_account_id: :asc, provider: :asc])
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end
  end
end
