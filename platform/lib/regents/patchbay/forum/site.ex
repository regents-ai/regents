defmodule Regents.Patchbay.Forum.Site do
  @moduledoc """
  A directory entry for a company, product, browser, platform, or website that
  has a documented relationship to WebMCP — and the board an agent lands on
  when it reports a tool on that origin.

  `origin` is a registrable domain (`openai.com`), so every host under it
  (`developers.openai.com`) files on the same board. Each tool keeps the exact
  address it was seen at.

  Catalog fields describe the official relationship. They are never inferred
  from a logo or a supporter banner. A site an agent merely named gets a domain
  slug and nothing else: its relationship and inventory stay unset until the
  catalog says otherwise.

  `claimed_at` and `claim_kind` describe a site whose owner has proved control
  of the origin. v0 has no way to set them: proving ownership needs a DNS TXT
  or well-known-file check that does not exist yet, and until it does, no
  caller may mark a site as claimed. Every site therefore reads as `:none`.

  The table and its rows as patchbay.help keeps them; nothing here reads or
  writes them yet.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Patchbay.Forum,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  import Ash.Expr

  alias Regents.Patchbay.Forum.Types.ClaimKind
  alias Regents.Patchbay.Forum.Types.EntityType
  alias Regents.Patchbay.Forum.Types.SupportRelationship
  alias Regents.Patchbay.Forum.Types.SupportStatus
  alias Regents.Patchbay.Forum.Types.ToolInventoryStatus

  postgres do
    table("forum_sites")
    schema("patchbay_app")
    repo(Regents.Repo)

    custom_indexes do
      # A search of the sites' addresses and names reads this instead of every site.
      index(
        [
          "to_tsvector('english'::regconfig, coalesce(origin, '') || ' ' || coalesce(display_name, ''))"
        ],
        name: "forum_sites_search_words_index",
        using: "GIN",
        concurrently: true
      )

      # A site match reads these: an address or name containing the typed
      # words, or nearly matching them.
      index(["origin public.gin_trgm_ops"],
        name: "forum_sites_origin_trgm_index",
        using: "GIN",
        concurrently: true
      )

      index(["display_name public.gin_trgm_ops"],
        name: "forum_sites_display_name_trgm_index",
        using: "GIN",
        concurrently: true
      )
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute :origin, :string do
      allow_nil?(false)
      public?(true)
      constraints(min_length: 1, max_length: 253)
    end

    attribute :slug, :string do
      allow_nil?(true)
      public?(true)
      constraints(min_length: 1, max_length: 80, match: ~r/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/)
    end

    attribute :display_name, :string do
      allow_nil?(true)
      public?(true)
      constraints(min_length: 1, max_length: 80)
    end

    attribute(:entity_type, EntityType, allow_nil?: true, public?: true)
    attribute(:organization_name, :string, allow_nil?: true, public?: true)
    attribute(:canonical_domain, :string, allow_nil?: true, public?: true)

    attribute(:support_relationship, SupportRelationship, allow_nil?: true, public?: true)
    attribute(:support_status, SupportStatus, allow_nil?: true, public?: true)
    attribute(:support_evidence_url, :string, allow_nil?: true, public?: true)
    attribute(:support_evidence_label, :string, allow_nil?: true, public?: true)
    attribute(:last_verified_at, :utc_datetime_usec, allow_nil?: true, public?: true)

    attribute(:tool_inventory_status, ToolInventoryStatus, allow_nil?: true, public?: true)

    attribute(:logo_path, :string, allow_nil?: true, public?: true)
    attribute(:logo_source_url, :string, allow_nil?: true, public?: true)
    attribute(:logo_usage_note, :string, allow_nil?: true, public?: true)
    attribute(:screenshot_path, :string, allow_nil?: true, public?: true)
    attribute(:screenshot_source_url, :string, allow_nil?: true, public?: true)
    attribute(:screenshot_captured_at, :utc_datetime_usec, allow_nil?: true, public?: true)
    attribute(:picture_failed_at, :utc_datetime_usec, allow_nil?: true, public?: true)
    attribute(:refreshed_at, :utc_datetime_usec, allow_nil?: true, public?: true)

    attribute(:featured_rank, :integer, allow_nil?: true, public?: true)

    attribute(:claimed_at, :utc_datetime_usec, allow_nil?: true, public?: true)
    attribute(:claim_kind, ClaimKind, allow_nil?: false, public?: true, default: :none)

    timestamps()
  end

  identities do
    identity(:unique_origin, [:origin])
    # Catalog upserts target origin. A pre-write check on the other identity
    # mistakes the same row's slug for a conflict; the unique SQL index still
    # rejects different origins claiming that slug, including concurrent writes.
    identity(:unique_slug, [:slug], eager_check?: false)
  end

  relationships do
    has_many(:tools, Regents.Patchbay.Forum.Tool)

    # What Patchbay last found on the site: the check's domain is the site's
    # registrable domain, its origin, and there is one check per domain.
    has_one :site_check, Regents.Patchbay.Forum.SiteCheck do
      source_attribute(:origin)
      destination_attribute(:domain)
    end

    # Every public thread on this board, whether or not it names a tool.
    has_many :reports, Regents.Patchbay.Forum.Report do
      filter(expr(visibility == :published))
    end
  end

  # No action is carried yet, so every action is refused; each comes with its own
  # policies.
  policies do
    policy always() do
      forbid_if(always())
    end
  end
end
