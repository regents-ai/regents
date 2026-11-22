defmodule Regents.Autolaunch.Token do
  @moduledoc """
  One launched token whose auction graduated: its name and symbol as its
  auction has them, its latest price and where its trades are read from next.

  The table and its rows as autolaunch.sh keeps them; nothing here reads or
  writes them yet.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Autolaunch,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

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
    belongs_to :auction, Regents.Autolaunch.Auction do
      allow_nil? false
      attribute_public? true
    end

    belongs_to :treasury_security_report,
               Regents.Autolaunch.TreasurySecurityReport do
      attribute_public? true
    end
  end

  identities do
    identity :unique_auction, [:auction_id]
  end

  # No action is carried yet, so every action is refused; each comes with its own
  # policies.
  policies do
    policy always() do
      forbid_if always()
    end
  end
end
