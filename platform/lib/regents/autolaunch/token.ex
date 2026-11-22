defmodule Regents.Autolaunch.Token do
  @moduledoc """
  One launched token whose auction graduated: its name and symbol as its
  auction has them, its latest price and where its trades are read from next.

  The table and its rows as autolaunch.sh keeps them. Autolaunch's lists read
  them (`Regents.Autolaunch.HomeMarket`); nothing here writes them yet.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Autolaunch,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    primary_read_warning?: false

  require Ash.Query
  alias Regents.Autolaunch.LinkedCreators

  # A subject id occupies one public URL segment, the identifier format the
  # public route catalog accepts.
  @subject_id_shape ~r/\A[a-zA-Z0-9][a-zA-Z0-9._:-]{0,127}\z/

  postgres do
    table "tokens"
    schema("autolaunch_app")
    repo(Regents.Repo)

    # The public token lists read their page straight off this in order.
    custom_indexes do
      index(["graduated_at DESC", "id"], name: "tokens_graduated_newest_index")
    end
  end

  attributes do
    uuid_primary_key :id

    # A token's name and symbol are its auction's, as the chain has them:
    # whatever an auction row admits, its token admits.
    attribute :name, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 160, trim?: true
    end

    attribute :symbol, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 16, trim?: true
    end

    attribute :summary, :string do
      public? true
      constraints max_length: 2_000, trim?: true
    end

    attribute :graduated_at, :utc_datetime_usec do
      allow_nil? false
      public? true
    end

    attribute :top_rank, :integer do
      public? true
      constraints min: 1
    end

    attribute :subject_id, :string do
      public? true
      constraints min_length: 1, max_length: 128, trim?: false, match: @subject_id_shape
    end

    attribute :price_quote, :string do
      public? true
      constraints max_length: 100, trim?: true
    end

    attribute :price_source, :string do
      public? true
      constraints max_length: 100, trim?: true
    end

    attribute :price_updated_at, :utc_datetime_usec do
      public? true
    end

    # Where the pool's trades are read from next, the hash of the block before
    # it, and when the next pass is due.
    attribute :trades_next_block, :integer
    attribute :trades_last_hash, :string

    attribute :treasury_address, :string do
      public? true
      constraints min_length: 42, max_length: 42, match: ~r/\A0x[0-9a-fA-F]{40}\z/
    end

    timestamps()
  end

  relationships do
    # Read through the listing rule, so a Robinhood launch's token reaches its
    # auction too.
    belongs_to :auction, Regents.Autolaunch.Auction do
      read_action :listed
      allow_nil? false
      attribute_public? true
    end

    belongs_to :treasury_security_report,
               Regents.Autolaunch.TreasurySecurityReport do
      attribute_public? true
    end
  end

  calculations do
    # What every token is worth at its current price, in the pool currency's units.
    calculate :market_cap, :decimal, Regents.Autolaunch.Token.Calculations.MarketCap do
      public? true
    end

    # How closely a search matches this token: its auction's match, or its own
    # name and ticker; see `Regents.Autolaunch.Search`.
    calculate :search_rank,
              :float,
              expr(
                fragment(
                  "greatest(?, word_similarity(?, concat_ws(' ', ?, ?)))",
                  auction.search_rank(term: ^arg(:term), address: ^arg(:address)),
                  ^arg(:term),
                  name,
                  symbol
                )
              ) do
      argument :term, :string, allow_nil?: false
      argument :address, :string
    end
  end

  identities do
    identity :unique_auction, [:auction_id]
  end

  actions do
    read :read do
      primary? true
      prepare Regents.Autolaunch.Token.Preparations.BaseAuctionOnly
    end

    read :home_market do
      argument :x, :boolean, default: false
      argument :ens, :boolean, default: false
      argument :github, :boolean, default: false
      argument :query, :string, default: "", constraints: [allow_empty?: true, max_length: 80]
      argument :chain, :string, default: "all", constraints: [match: ~r/\A(all|base|robinhood)\z/]

      argument :kind, :string,
        default: "all",
        constraints: [match: ~r/\A(all|revstake|memestock)\z/]

      pagination keyset?: true, required?: true, default_limit: 24, max_page_size: 100
      prepare Regents.Autolaunch.Token.Preparations.ListedAuction
      prepare Regents.Autolaunch.Token.Preparations.ShownAuction

      # A query with a value the list does not know is refused as it stands.
      prepare fn
        %{valid?: false} = query, _context ->
          query

        query, _context ->
          query =
            case query.arguments.chain do
              "base" ->
                Ash.Query.filter(query, auction.chain_id == ^Regents.Autolaunch.Lab.chain_id())

              "robinhood" ->
                Ash.Query.filter(
                  query,
                  auction.chain_id == ^Regents.Autolaunch.Robinhood.Lab.chain_id()
                )

              "all" ->
                query
            end

          query =
            case query.arguments.kind do
              "revstake" -> Ash.Query.filter(query, auction.kind == :agent)
              "memestock" -> Ash.Query.filter(query, auction.kind == :stocks)
              "all" -> query
            end

          # The creators holding each linked account the filters ask about, read once.
          holders =
            LinkedCreators.holding!(Enum.filter([:x, :ens, :github], &query.arguments[&1]))

          query =
            if query.arguments.x,
              do:
                Ash.Query.filter(
                  query,
                  exists(auction.creator_x_connections, not is_nil(verified_at)) or
                    auction.creator_human_account_id in ^holders.x
                ),
              else: query

          query =
            if query.arguments.ens,
              do: Ash.Query.filter(query, auction.creator_human_account_id in ^holders.ens),
              else: query

          query =
            if query.arguments.github,
              do: Ash.Query.filter(query, auction.creator_human_account_id in ^holders.github),
              else: query

          query
          |> Ash.Query.load([:treasury_security_report, :auction])
          |> Regents.Autolaunch.Search.rank(query.arguments.query, graduated_at: :desc, id: :asc)
      end
    end
  end

  # Only the reads the lists use are carried; any other action is refused until
  # it comes with its own policy.
  policies do
    policy action([:read, :home_market]) do
      authorize_if always()
    end
  end
end
