defmodule Regents.Autolaunch.Auction do
  @moduledoc """
  One launch's auction on one chain: what the launch recorded when it opened,
  the creator's links and picture, and the latest figures read from its
  contract.

  The table and its rows as autolaunch.sh keeps them; nothing here reads or
  writes them yet.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Autolaunch,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

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

  identities do
    identity :chain_auction, [:chain_id, :auction_address]
  end

  # No action is carried yet, so every action is refused; each comes with its own
  # policies.
  policies do
    policy always() do
      forbid_if always()
    end
  end
end
