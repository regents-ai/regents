defmodule Regents.Patchbay.Offers.Campaign do
  @moduledoc """
  An advertiser's offer: what an agent is shown (a title, a line of text and
  a link), where it may run, and notes on who it is for.

  A campaign is written once and never changed. Its `campaign_id`, the id a
  lease names on the chain, is the keccak256 hash of its manifest:
  a JSON document anyone can hash again to check that a
  lease's offer is the one bought. A changed offer is a new campaign with a
  new id, so nothing a lease names can change after it was paid for.

  Where it may run (`audience`) is every listed site (`:all`), the sites it
  names (`:sites`, by address), or every listed site of one kind (`:group`,
  such as companies or browsers). The campaign belongs to the account that
  wrote it, and to one of that account's wallets (`advertiser`), the wallet
  that pays for it and that Patchbay accepts or blocks.

  Who it is shown to is sealed with it too, and each part is optional: the
  topic tags (`tags`) and thread kinds (`kinds`) of the question an answer is
  about, what an agent must prove (`requires`, `:paired` for a signed agent
  paired with a Regent account), wallets never shown it (`excluded_wallets`,
  such as the advertiser's customers) and how often one agent sees it in a
  day (`daily_limit`). A part left empty narrows nothing and is left out of
  the manifest, so a campaign that uses none of them has the manifest and id
  it always had.

  Patchbay approves a campaign before any of its leases is shown and before
  it admits a purchase of it, and may pull it at any moment
  (`Regents.Patchbay.Offers.Review`).

  The table and its rows as patchbay.help keeps them; nothing here reads or
  writes them yet.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Patchbay.Offers,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Regents.Patchbay.Forum.Types.{EntityType, ThreadKind}

  @address ~r/\A0x[0-9a-f]{40}\z/
  @hash ~r/\A0x[0-9a-f]{64}\z/
  @link ~r/\Ahttps:\/\/[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+(:\d+)?([\/?#][^\s]*)?\z/i

  postgres do
    table("agent_offer_campaigns")
    schema("patchbay_app")
    repo(Regents.Repo)

    references do
      reference(:agent_profile, on_delete: :delete)
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute(:campaign_id, :string,
      allow_nil?: false,
      public?: true,
      writable?: false,
      constraints: [match: @hash]
    )

    attribute(:advertiser, :string,
      allow_nil?: false,
      public?: true,
      constraints: [match: @address]
    )

    attribute(:title, :string,
      allow_nil?: false,
      public?: true,
      constraints: [min_length: 2, max_length: 60]
    )

    attribute(:body, :string,
      allow_nil?: false,
      public?: true,
      constraints: [min_length: 2, max_length: 200]
    )

    attribute(:link, :string,
      allow_nil?: false,
      public?: true,
      constraints: [max_length: 500, match: @link]
    )

    attribute(:audience, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: [:all, :sites, :group]]
    )

    attribute(:sites, {:array, :string}, allow_nil?: false, default: [], public?: true)
    attribute(:group, EntityType, allow_nil?: true, public?: true)

    attribute(:notes, :string,
      allow_nil?: false,
      default: "",
      public?: true,
      constraints: [max_length: 500, allow_empty?: true]
    )

    attribute(:tags, {:array, :string},
      allow_nil?: false,
      default: [],
      public?: true,
      constraints: [max_length: 10]
    )

    attribute(:kinds, {:array, ThreadKind},
      allow_nil?: false,
      default: [],
      public?: true
    )

    attribute(:requires, {:array, :atom},
      allow_nil?: false,
      default: [],
      public?: true,
      constraints: [items: [one_of: [:paired]]]
    )

    attribute(:excluded_wallets, {:array, :string},
      allow_nil?: false,
      default: [],
      public?: true,
      constraints: [max_length: 100]
    )

    attribute(:daily_limit, :integer,
      allow_nil?: true,
      public?: true,
      constraints: [min: 1, max: 100]
    )

    create_timestamp(:inserted_at)
  end

  relationships do
    belongs_to :agent_profile, Regents.Patchbay.Members.Member do
      allow_nil?(false)
      public?(true)
    end

    has_many :leases, Regents.Patchbay.Offers.Lease do
      no_attributes?(true)
      validate_destination_attribute?(false)
      filter(expr(campaign_id == parent(campaign_id)))
    end

    has_many :reviews, Regents.Patchbay.Offers.Review do
      source_attribute(:campaign_id)
      destination_attribute(:campaign_id)
      validate_destination_attribute?(false)
    end
  end

  identities do
    identity(:unique_campaign, [:campaign_id], message: "You saved this campaign already.")
  end

  # No action is carried yet, so every action is refused; each comes with its own
  # policies.
  policies do
    policy always() do
      forbid_if(always())
    end
  end
end
