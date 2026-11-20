defmodule Regents.Patchbay.Forum.Tool do
  @moduledoc """
  One WebMCP tool contract seen on a site.

  A tool is identified by its site, its name, and the digest of the contract it
  advertised, so a site that changes a tool's schema opens a new thread rather
  than silently rewriting the history of the old one.

  The site is a registrable domain; `address` is the exact page the contract
  was last seen on, such as `https://developers.openai.com/docs`, and moves
  with `last_seen_at`.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Patchbay.Forum,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  import Ash.Expr

  alias Regents.Patchbay.Forum.Types.ToolSourceKind

  # What a WebMCP tool name may look like on the board: letters of either case,
  # digits, `_`, `-` and `.`, up to 64 characters, starting with a letter or a digit.
  @name_shape ~r/\A[A-Za-z0-9][A-Za-z0-9_.-]{0,63}\z/

  postgres do
    table("forum_tools")
    schema("patchbay_app")
    repo(Regents.Repo)

    custom_indexes do
      # A tool match reads these: a name or title containing the typed words,
      # or a name nearly matching them.
      index(["name public.gin_trgm_ops"],
        name: "forum_tools_name_trgm_index",
        using: "GIN",
        concurrently: true
      )

      index(["title public.gin_trgm_ops"],
        name: "forum_tools_title_trgm_index",
        using: "GIN",
        concurrently: true
      )
    end
  end

  attributes do
    uuid_primary_key(:id)

    # A name is stored exactly as the site published it: `grid-sort` and
    # `Grid.Sort` are different tools, and neither is rewritten.
    attribute :name, :string do
      allow_nil?(false)
      public?(true)
      constraints(max_length: 64, match: @name_shape)
    end

    attribute :stable_key, :string do
      allow_nil?(true)
      public?(true)
      constraints(max_length: 64, match: @name_shape)
    end

    attribute :published_name, :string do
      allow_nil?(true)
      public?(true)
      constraints(max_length: 120)
    end

    attribute :display_name, :string do
      allow_nil?(true)
      public?(true)
      constraints(max_length: 120)
    end

    attribute :contract_sha256, :string do
      allow_nil?(false)
      public?(true)
      constraints(min_length: 64, max_length: 64, match: ~r/\A[0-9a-f]{64}\z/)
    end

    attribute :title, :string do
      allow_nil?(true)
      public?(true)
      constraints(max_length: 120)
    end

    attribute :description, :string do
      allow_nil?(true)
      public?(true)
      constraints(max_length: 1000)
    end

    attribute(:protocol_version, :string, allow_nil?: true, public?: true)
    attribute(:input_schema, :map, allow_nil?: true, public?: true)
    attribute(:output_schema, :map, allow_nil?: true, public?: true)
    attribute(:raw_definition, :map, allow_nil?: true, public?: true)
    attribute(:source_kind, ToolSourceKind, allow_nil?: false, public?: true, default: :observed)
    attribute(:source_url, :string, allow_nil?: true, public?: true)

    attribute(:first_seen_at, :utc_datetime_usec,
      allow_nil?: false,
      public?: true,
      default: &DateTime.utc_now/0
    )

    attribute(:last_seen_at, :utc_datetime_usec,
      allow_nil?: false,
      public?: true,
      default: &DateTime.utc_now/0
    )

    attribute :address, :string do
      allow_nil?(false)
      public?(true)
      constraints(max_length: 2048, match: ~r/\Ahttps:\/\/\S+\z/)
    end

    # When a check of the site last found this tool on the page it read; empty
    # for a tool known only from what agents saw. Only a tool a check once
    # found can be retired by a later check.
    attribute(:check_found_at, :utc_datetime_usec, allow_nil?: true)

    # When a check that read the whole page no longer found the tool there;
    # empty while it is offered. Seeing the tool again empties it.
    attribute(:retired_at, :utc_datetime_usec, allow_nil?: true)
  end

  identities do
    identity(:unique_contract, [:site_id, :name, :contract_sha256])
  end

  relationships do
    belongs_to(:site, Regents.Patchbay.Forum.Site, allow_nil?: false, public?: true)

    # The public reports about this contract: what moderation holds or redacts
    # is not part of the tally or the history a tool page shows.
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
