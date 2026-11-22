defmodule Regents.Autolaunch.Robinhood.LaunchReview do
  @moduledoc """
  A Robinhood launch this site prepared for one of its accounts, stored when the
  review is built so the launch is known as the site's even if the creator's
  browser never reports it back.

  Each launch found on Robinhood is matched to these reviews: one whose wallet
  launched it with exactly the reviewed name, symbol and stock makes it a site
  launch, in that review's account, with the Telegram, Discord and other links
  the review carried; no match makes it a launch seen only on chain. The
  review a launch is listed from is marked `adopted_at` in the same write as
  the listing. A paired agent's review of the person's draft is
  `prepared_by: :agent`.

  The table and its rows as autolaunch.sh keeps them; nothing here reads or
  writes them yet.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Autolaunch,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "robinhood_launch_reviews"
    schema("autolaunch_app")
    repo(Regents.Repo)
  end

  attributes do
    uuid_primary_key :id

    attribute :chain_id, :integer, allow_nil?: false, constraints: [min: 1]

    # Addresses are stored lowercase.
    attribute :signer, :string, allow_nil?: false, constraints: [min_length: 42, max_length: 42]
    attribute :human_account_id, :integer, allow_nil?: false
    attribute :name, :string, allow_nil?: false, constraints: [trim?: false]
    attribute :symbol, :string, allow_nil?: false, constraints: [trim?: false]
    attribute :stock, :string, allow_nil?: false, constraints: [min_length: 42, max_length: 42]
    attribute :telegram, :string, constraints: [max_length: 256]
    attribute :discord, :string, constraints: [max_length: 256]

    attribute :links, {:array, :string},
      allow_nil?: false,
      default: [],
      constraints: [max_length: 3, items: [max_length: 256]]

    # Set only by a paired agent's preparation.
    attribute :prepared_by, :atom,
      allow_nil?: false,
      default: :person,
      constraints: [one_of: [:person, :agent]]

    # Nil until a launch is listed from this review.
    attribute :adopted_at, :utc_datetime_usec

    create_timestamp :inserted_at
  end

  # No action is carried yet, so every action is refused; each comes with its own
  # policies.
  policies do
    policy always() do
      forbid_if always()
    end
  end
end
