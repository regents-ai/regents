defmodule Regents.Autolaunch.Stocks.StockCandidate do
  @moduledoc """
  A stock Chainlink prices on a launch chain that the chain's stock launchpad
  does not admit: a candidate for the Safe to admit, with what the last look
  found of it. One row per chain and ticker. The row says one of:

  - `:qualifies`: the feed answers and the issuer's token has a dollar pool
    with more than $10,000 in it.
  - `:thin_pool`: its deepest dollar pool holds $10,000 or less.
  - `:no_dollar_pool`: no dollar pool of the issuer's token was found.
  - `:feed_silent`: the feed gives no price, or one more than seven days old.
  - `:unread`: listed and not read yet.

  The rows are advice for the people who sign an admission, and nothing more.
  The feed list and the pool figures come from outside services, and nothing
  here proves a token is the issuer's own: the marks checked can be copied.
  No launch, bid, picker or price reads this table; those read
  `Regents.Autolaunch.Stocks.Stock`, which is written only from the
  launchpads' own answers.

  The table and its rows as autolaunch.sh keeps them; nothing here reads or
  writes them yet.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Autolaunch,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "stock_candidates"
    schema("autolaunch_app")
    repo(Regents.Repo)
  end

  attributes do
    uuid_primary_key :id

    attribute :chain_id, :integer, allow_nil?: false, constraints: [min: 1]

    # The exchange ticker, as Chainlink's list names the feed.
    attribute :ticker, :string,
      allow_nil?: false,
      constraints: [match: ~r/\A[A-Z0-9.]{1,12}\z/]

    attribute :feed, :string,
      allow_nil?: false,
      constraints: [match: ~r/\A0x[0-9a-f]{40}\z/]

    attribute :status, :atom,
      allow_nil?: false,
      default: :unread,
      constraints: [one_of: [:unread, :qualifies, :thin_pool, :no_dollar_pool, :feed_silent]]

    # The issuer's token and its deepest dollar pool at the last read: the
    # pool as GeckoTerminal names it (an address, or a pool id on Uniswap v4),
    # the venue under GeckoTerminal's name for it, and the USD in the pool.
    attribute :token, :string, constraints: [match: ~r/\A0x[0-9a-f]{40}\z/]
    attribute :pool, :string, constraints: [max_length: 120]
    attribute :venue, :string, constraints: [max_length: 80]
    attribute :liquidity_usd, :decimal, constraints: [min: 0]
    attribute :read_at, :utc_datetime_usec

    # When the row was last tried, read or not: the order of the rounds.
    attribute :tried_at, :utc_datetime_usec

    timestamps()
  end

  identities do
    identity :chain_ticker, [:chain_id, :ticker]
  end

  # No action is carried yet, so every action is refused; each comes with its own
  # policies.
  policies do
    policy always() do
      forbid_if always()
    end
  end
end
