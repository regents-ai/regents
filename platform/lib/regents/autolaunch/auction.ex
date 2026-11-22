defmodule Regents.Autolaunch.Auction do
  @moduledoc """
  One launch's auction on one chain: what the launch recorded when it opened,
  the creator's links and picture, and the latest figures read from its
  contract.

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

  postgres do
    table "auctions"
    schema("autolaunch_app")
    repo(Regents.Repo)

    # Each public list reads its page straight off one of these in order.
    custom_indexes do
      index([:estimated_end_at, :id], name: "auctions_ending_index")
      index(["bid_volume_usd DESC NULLS LAST", "id"], name: "auctions_bid_volume_index")

      index(["inserted_at DESC", "id"], name: "auctions_home_newest_index")
      index([:kind, :state], name: "auctions_kind_state_index")
    end
  end

  attributes do
    attribute :activity_next_block, :integer
    attribute :activity_last_hash, :string
    attribute :bid_volume, :decimal, public?: true
    attribute :bid_volume_usd, :decimal, public?: true
    attribute :estimated_end_at, :utc_datetime_usec, public?: true
    uuid_primary_key :id

    attribute :title, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 160, trim?: true
    end

    attribute :summary, :string do
      public? true
      constraints max_length: 2_000, trim?: true
    end

    attribute :token_symbol, :string do
      public? true
      constraints max_length: 16, trim?: true
    end

    attribute :website, :string do
      public? true
      constraints max_length: 256, trim?: true
    end

    # The creator's Telegram group, Discord invite and up to three other links,
    # kept by this site: they are not part of the token's onchain metadata.
    attribute :telegram, :string do
      public? true
      constraints max_length: 256, trim?: true
    end

    attribute :discord, :string do
      public? true
      constraints max_length: 256, trim?: true
    end

    attribute :links, {:array, :string} do
      public? true
      allow_nil? false
      default []
      constraints max_length: 3, items: [max_length: 256, trim?: true]
    end

    attribute :image, :string do
      public? true
      constraints max_length: 256, trim?: true
    end

    # The colour of the image, when the image is one the site stores.
    attribute :image_color, :string do
      public? true
      constraints match: ~r/\A#[0-9a-f]{6}\z/, max_length: 7
    end

    attribute :featured, :boolean do
      allow_nil? false
      public? true
      default false
    end

    # Off every public list and page while true.
    attribute :hidden, :boolean do
      allow_nil? false
      default false
    end

    # Which launch mode created this auction. Agent auctions raise REGENT;
    # Stocks auctions raise the admitted Base stock token named by the quote
    # token fields.
    attribute :kind, :atom do
      allow_nil? false
      public? true
      default :agent
      constraints one_of: [:agent, :stocks]
    end

    # The contracts a launch runs on, which are the only ones it reads. The
    # first four Memestock launches (BITE, JollyB and AGI on Base, RDOG on
    # Robinhood) are `:v1`, on their original launchpad, hook and locker. A
    # Base launch is recorded with the version of the contracts that made it:
    # `:v2` until 12 November 2026, `:v3` since. Robinhood's later launches are
    # `:v2`. Every writer names the version; there is no default.
    attribute :contracts_version, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:v1, :v2, :v3]
    end

    # Where the launch came from: `:site` when this site prepared it (on Base,
    # a review this site's account carried out; on Robinhood, a review stored
    # when the site prepared it), `:chain` when it was only seen on chain.
    # Site launches and every Base Memestock launch are listed.
    attribute :origin, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:site, :chain]
    end

    attribute :state, :atom do
      allow_nil? false
      public? true
      default :created
      constraints one_of: [:created, :active, :ended, :graduated, :failed]
    end

    # The raise has met its minimum. A progress fact only: bidding stays open
    # until the end block, and only the launch's own finish makes it final.
    attribute :minimum_reached, :boolean do
      allow_nil? false
      public? true
      default false
    end

    attribute :opened_at, :utc_datetime_usec do
      public? true
    end

    # One auction contract on one chain is one row; the same address on
    # another chain is another auction.
    attribute :chain_id, :integer do
      public? true
      allow_nil? false
      constraints min: 1
    end

    attribute :auction_address, :string do
      public? true
      allow_nil? false
      constraints min_length: 42, max_length: 42, match: ~r/\A0x[0-9a-fA-F]{40}\z/
    end

    attribute :quote_token_address, :string do
      public? true
      constraints min_length: 42, max_length: 42, match: ~r/\A0x[0-9a-fA-F]{40}\z/
    end

    attribute :quote_token_symbol, :string do
      public? true
      constraints min_length: 1, max_length: 32, trim?: true
    end

    attribute :quote_token_decimals, :integer do
      public? true
      constraints min: 0, max: 36
    end

    attribute :current_clearing_price, :string do
      public? true
      constraints max_length: 100, trim?: true
    end

    # The latest reading of what the auction has raised, in whole quote-token
    # units.
    attribute :currency_raised, :decimal do
      public? true
    end

    # The lowest price the auction sells at, in quote-token units per token,
    # and the launch token's total supply in whole tokens. Both are fixed when
    # the auction is created; its reading job reads them once.
    attribute :floor_price, :string do
      public? true
      constraints max_length: 100, trim?: true
    end

    attribute :token_supply, :decimal do
      public? true
    end

    attribute :treasury_address, :string do
      public? true
      constraints min_length: 42, max_length: 42, match: ~r/\A0x[0-9a-fA-F]{40}\z/
    end

    # The wallet that launched the auction on chain, in lowercase.
    attribute :creator_address, :string do
      public? true
      allow_nil? false
      constraints min_length: 42, max_length: 42, match: ~r/\A0x[0-9a-f]{40}\z/
    end

    # What the auction must raise to graduate, in the quote token's smallest
    # units. The auction contract keeps it without a getter, so the launch
    # that set it is the record of it.
    attribute :required_currency_raised, :string do
      public? true
      allow_nil? false
      constraints match: ~r/\A[1-9][0-9]{0,38}\z/
    end

    # What the launch recorded when its auction opened: the token it sells, on
    # every launch; a Robinhood launch also its launch number on the launchpad
    # and its bidding window.
    attribute :token_address, :string do
      public? true
      constraints min_length: 42, max_length: 42, match: ~r/\A0x[0-9a-fA-F]{40}\z/
    end

    attribute :launch_id, :integer do
      public? true
      constraints min: 1
    end

    attribute :start_block, :integer do
      public? true
      constraints min: 0
    end

    attribute :end_block, :integer do
      public? true
      constraints min: 0
    end

    timestamps()
  end

  relationships do
    # The account whose signed-in wallet launched the auction. Every launch
    # made through this site's review has one; a Base Memestock launch sent
    # straight to the launchpad names only its wallet, and a Robinhood launch
    # names one only when exactly one account's signed-in wallet is its
    # launcher.
    belongs_to :creator_human_account, Regents.Account.Accounts.HumanAccount do
      allow_nil? true
      attribute_public? true
      attribute_type :integer
    end

    # The creator's verified links that name a username, regents.sh's. Read,
    # with the two aggregates over it, only through
    # `Regents.Autolaunch.Auction.Calculations.CreatorIdentities`, which leaves
    # them unread on the read-only venue.
    has_many :creator_identities, Regents.Account.Accounts.PublicLink do
      source_attribute :creator_human_account_id
      destination_attribute :human_account_id
    end

    has_many :creator_x_connections, Regents.Autolaunch.XConnection do
      source_attribute :creator_human_account_id
      destination_attribute :human_account_id
    end

    belongs_to :treasury_security_report,
               Regents.Autolaunch.TreasurySecurityReport do
      attribute_public? true
    end

    # The stock a Stocks auction raises, when the site lists it.
    has_one :quote_stock, Regents.Autolaunch.Stocks.Stock do
      no_attributes? true

      filter expr(
               chain_id == parent(chain_id) and
                 string_downcase(address) == string_downcase(parent(quote_token_address))
             )
    end
  end

  calculations do
    # What every token is worth at the current clearing price, in quote-token units.
    calculate :fdv, :decimal, Regents.Autolaunch.Auction.Calculations.Fdv do
      public? true
    end

    # The end of the contract address the auction's page addresses carry.
    calculate :path_tail, :string, Regents.Autolaunch.Auction.Calculations.PathTail do
      public? true
    end

    # How closely a search matches this auction, from 0 to 1; see `Regents.Autolaunch.Search`.
    # The name, ticker and stock count fully, the creator's accounts a little
    # less and the description less again. `address` is set when the search
    # could be part of an address, and matches the auction, token and creator
    # wallet outright.
    calculate :search_rank,
              :float,
              expr(
                if not is_nil(^arg(:address)) and
                     (contains(string_downcase(auction_address), ^arg(:address)) or
                        contains(string_downcase(token_address), ^arg(:address)) or
                        contains(creator_address, ^arg(:address))) do
                  1.0
                else
                  fragment(
                    "greatest(word_similarity(?, concat_ws(' ', ?, ?, ?, ?)), 0.9 * word_similarity(?, array_to_string(? || ? || ?, ' ')), 0.7 * word_similarity(?, coalesce(?, '')))",
                    ^arg(:term),
                    title,
                    token_symbol,
                    quote_token_symbol,
                    quote_stock_search_text,
                    ^arg(:term),
                    creator_identity_search_names,
                    creator_x_names,
                    creator_x_display_names,
                    ^arg(:term),
                    summary
                  )
                end
              ) do
      argument :term, :string, allow_nil?: false
      argument :address, :string
    end

    # Whether the creator holds a linked account of `provider`, for the lists'
    # filters, and their linked accounts' names, for search; see
    # `Regents.Autolaunch.Auction.Calculations.CreatorIdentities`.
    calculate :creator_linked,
              :boolean,
              {Regents.Autolaunch.Auction.Calculations.CreatorIdentities, answer: :linked} do
      argument :provider, :atom, allow_nil?: false, constraints: [one_of: [:x, :ens, :github]]
    end

    calculate :creator_identity_search_names,
              {:array, :string},
              {Regents.Autolaunch.Auction.Calculations.CreatorIdentities, answer: :names}

    # The creator's linked X, ENS and GitHub usernames, for their links beside
    # a launch on the lists; see the same module.
    calculate :creator_links,
              :map,
              {Regents.Autolaunch.Auction.Calculations.CreatorIdentities, answer: :links} do
      constraints fields: [x: [type: :string], ens: [type: :string], github: [type: :string]]
    end
  end

  aggregates do
    # The creator's connected account names, for search.
    list :creator_identity_names, :creator_identities, :username do
      filter expr(provider in [:x, :github, :ens])
    end

    list :creator_identity_display_names, :creator_identities, :display_name do
      filter expr(provider in [:x, :github, :ens])
    end

    list :creator_x_names, :creator_x_connections, :username do
      filter expr(not is_nil(verified_at))
    end

    list :creator_x_display_names, :creator_x_connections, :display_name do
      filter expr(not is_nil(verified_at))
    end

    first :quote_stock_search_text, :quote_stock, :search_text
  end

  identities do
    identity :chain_auction, [:chain_id, :auction_address]
  end

  actions do
    read :read do
      primary? true
      prepare Regents.Autolaunch.Auction.Preparations.BaseOnly
    end

    # Every auction the public lists carry, on both chains.
    read :listed do
      prepare Regents.Autolaunch.Auction.Preparations.Listed
      prepare build(load: [:path_tail])
    end

    read :home_market do
      argument :x, :boolean, default: false
      argument :ens, :boolean, default: false
      argument :github, :boolean, default: false
      argument :query, :string, default: "", constraints: [allow_empty?: true, max_length: 80]
      argument :view, :string, default: "active", constraints: [match: ~r/\A(active|new)\z/]

      argument :state, :string,
        default: "all",
        constraints: [match: ~r/\A(all|created|active|ended|failed|graduated|finished)\z/]

      argument :sort, :string,
        default: "newest",
        constraints: [match: ~r/\A(newest|ending|volume)\z/]

      argument :chain, :string, default: "all", constraints: [match: ~r/\A(all|base|robinhood)\z/]

      argument :kind, :string,
        default: "all",
        constraints: [match: ~r/\A(all|revstake|memestock)\z/]

      pagination keyset?: true, required?: true, default_limit: 24, max_page_size: 50
      prepare Regents.Autolaunch.Auction.Preparations.Listed
      prepare Regents.Autolaunch.Auction.Preparations.Shown

      # A query with a value the list does not know is refused as it stands.
      prepare fn
        %{valid?: false} = query, _context ->
          query

        query, _context ->
          states =
            if query.arguments.view == "active",
              do: [:created, :active, :ended],
              else: [:created, :active, :ended, :failed, :graduated]

          states =
            Enum.filter(
              states,
              &(query.arguments.state == "all" or Atom.to_string(&1) == query.arguments.state or
                  (query.arguments.state == "finished" and &1 in [:graduated, :failed]))
            )

          query =
            case query.arguments.chain do
              "base" ->
                Ash.Query.filter(query, chain_id == ^Regents.Autolaunch.Lab.chain_id())

              "robinhood" ->
                Ash.Query.filter(query, chain_id == ^Regents.Autolaunch.Robinhood.Lab.chain_id())

              "all" ->
                query
            end

          query =
            case query.arguments.kind do
              "revstake" -> Ash.Query.filter(query, kind == :agent)
              "memestock" -> Ash.Query.filter(query, kind == :stocks)
              "all" -> query
            end

          query =
            if query.arguments.x,
              do:
                Ash.Query.filter(
                  query,
                  exists(creator_x_connections, not is_nil(verified_at)) or
                    creator_linked(provider: :x)
                ),
              else: query

          query =
            if query.arguments.ens,
              do: Ash.Query.filter(query, creator_linked(provider: :ens)),
              else: query

          query =
            if query.arguments.github,
              do: Ash.Query.filter(query, creator_linked(provider: :github)),
              else: query

          order =
            case query.arguments.sort do
              "ending" -> [estimated_end_at: :asc_nils_last, id: :asc]
              "volume" -> [bid_volume_usd: :desc_nils_last, id: :asc]
              "newest" -> [inserted_at: :desc, id: :asc]
            end

          query =
            if query.arguments.sort == "ending",
              do: Ash.Query.filter(query, state == :active),
              else: query

          query
          |> Ash.Query.filter(state in ^states)
          |> Ash.Query.load([:treasury_security_report, :path_tail])
          |> Regents.Autolaunch.Search.rank(query.arguments.query, order)
      end
    end

    # The listed auctions sharing any of these tickers, ignoring case, which
    # decide how much of each address its page address needs; see
    # `Regents.Autolaunch.Auction.Calculations.PathTail`.
    read :path_peers do
      argument :symbols, {:array, :string}, allow_nil?: false
      filter expr(string_downcase(token_symbol) in ^arg(:symbols))
      prepare Regents.Autolaunch.Auction.Preparations.Listed
      prepare Regents.Autolaunch.Auction.Preparations.Shown
    end
  end

  # Only the reads the lists use are carried; any other action is refused until
  # it comes with its own policy.
  policies do
    policy action([:read, :listed, :path_peers, :home_market]) do
      authorize_if always()
    end
  end
end
