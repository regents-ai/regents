defmodule Regents.Autolaunch.Stocks.Stock do
  @moduledoc """
  A stock token a launchpad has admitted as a launch currency, one row per
  chain and token address. This table is the site's one list of stocks: the
  picker, search, prices and every action's stock facts read it.

  Each row holds what the chain said of the stock at the last sync: whether it
  is admitted, its decimals and route, the route's price feed, and the token's
  own name and ticker. A row is not proof of admission at the moment of an
  action: the launchpad's `stockAdmission` is read again before every launch
  and bid. A revoked stock keeps its row, so auctions already trading in it
  stay findable by its name.

  The table and its rows as autolaunch.sh keeps them; nothing here reads or
  writes them yet.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Autolaunch,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "stocks"
    schema("autolaunch_app")
    repo(Regents.Repo)
  end

  attributes do
    uuid_primary_key :id

    attribute :chain_id, :integer, allow_nil?: false, public?: true

    attribute :address, :string,
      allow_nil?: false,
      public?: true,
      constraints: [match: ~r/\A0x[0-9a-f]{40}\z/]

    attribute :symbol, :string, allow_nil?: false, public?: true, constraints: [max_length: 32]
    attribute :name, :string, allow_nil?: false, public?: true, constraints: [max_length: 120]

    # What the launchpad and the route said at the last sync. A row written
    # before the site read admissions has none of these until its first sync.
    # A route that names no feed gives the stock no dollar price.
    attribute :admitted, :boolean, allow_nil?: false, default: false, public?: true
    attribute :decimals, :integer, public?: true, constraints: [min: 0, max: 36]
    attribute :route, :string, public?: true, constraints: [match: ~r/\A0x[0-9a-f]{40}\z/]
    attribute :feed, :string, public?: true, constraints: [match: ~r/\A0x[0-9a-f]{40}\z/]

    attribute :search_words, {:array, :string},
      allow_nil?: false,
      default: [],
      public?: true,
      constraints: [items: [max_length: 80]]

    # The USD traded in the stock's dollar-token pools over the seven UTC days
    # ending on `weekly_volume_through`; a floor when not complete, because
    # GeckoTerminal listed the stock's pools over more than one page.
    attribute :weekly_volume_usd, :decimal, public?: true, constraints: [min: 0]
    attribute :weekly_volume_complete, :boolean, allow_nil?: false, default: false, public?: true
    attribute :weekly_volume_through, :date, public?: true

    # When this site first listed the stock: when its row was first written.
    # Stocks it listed before it kept this record have none.
    attribute :offered_at, :utc_datetime_usec, public?: true

    timestamps()
  end

  identities do
    identity :chain_address, [:chain_id, :address]
  end

  # No action is carried yet, so every action is refused; each comes with its own
  # policies.
  policies do
    policy always() do
      forbid_if always()
    end
  end
end
