defmodule Regents.Autolaunch.AuctionReading do
  @moduledoc """
  An auction's last reading of its own contract, one row per auction: its
  figures (`Regents.Autolaunch.AuctionReading.Market`) and, for a Base auction,
  everything its own page shows (`Regents.Autolaunch.AuctionReading.Page`).
  `read_block` and `block_hash` name the block it was read at; `degraded` says
  the last attempt to read it again failed, so it is shown as it was. Every
  field is public on the chain itself. `version` is set by the database and a
  page keeps the newer.

  The table and its rows as autolaunch.sh keeps them; nothing here reads or
  writes them yet.
  """
  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Autolaunch,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Regents.Autolaunch.AuctionReading.{Market, Page}

  postgres do
    table "auction_readings"
    schema("autolaunch_app")
    repo(Regents.Repo)

    references do
      reference(:auction, on_delete: :delete)
    end
  end

  attributes do
    attribute :read_block, :integer, allow_nil?: false, public?: true
    attribute :block_hash, :string, allow_nil?: false, public?: true
    attribute :read_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :degraded, :boolean, allow_nil?: false, default: false, public?: true
    attribute :version, :integer, allow_nil?: false, default: 1, public?: true
    attribute :market, Market, allow_nil?: false, public?: true
    attribute :page, Page, public?: true
  end

  relationships do
    belongs_to :auction, Regents.Autolaunch.Auction do
      primary_key? true
      allow_nil? false
      attribute_writable? true
      public? true
    end
  end

  # No action is carried yet, so every action is refused; each comes with its own
  # policies.
  policies do
    policy always() do
      forbid_if always()
    end
  end
end
