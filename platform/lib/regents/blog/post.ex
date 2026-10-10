defmodule Regents.Blog.Post do
  @moduledoc "Public articles created by verified admins or the folder release command."
  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Blog,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  require Ash.Query

  @fields ~w(slug title description date author author_x authors markdown draft cover cover_type cover_alt)a

  actions do
    create :put do
      accept @fields
      upsert? true
      upsert_identity :unique_slug
      upsert_fields List.delete(@fields, :slug) ++ [:updated_at]
    end

    create :publish do
      accept [:title, :date, :authors, :markdown, :cover, :cover_alt]
      change Regents.Blog.Changes.Publish
    end

    read :list do
      prepare build(sort: [date: :desc, slug: :asc], deselect: [:cover, :markdown])
    end

    read :post do
      argument :slug, :string, allow_nil?: false
      get? true
      filter expr(slug == ^arg(:slug))
      prepare build(deselect: [:cover])
    end

    read :cover do
      argument :slug, :string, allow_nil?: false
      get? true
      filter expr(slug == ^arg(:slug))
      prepare build(select: [:slug, :cover, :cover_type, :updated_at])
    end
  end

  changes do
    change Regents.Blog.Changes.ValidateContent
  end

  preparations do
    prepare fn query, _context ->
      Ash.Query.filter(query, draft == false and date <= ^Date.utc_today())
    end
  end

  policies do
    policy action(:put) do
      authorize_if Regents.Checks.SystemActor
    end

    policy action(:publish) do
      authorize_if Regents.Blog.Checks.Admin
    end

    policy action_type(:read) do
      authorize_if always()
    end
  end

  validations do
    validate match(:slug, ~r/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/)
    validate match(:author_x, ~r"\Ahttps://(?:x|twitter)\.com/[A-Za-z0-9_]{1,15}/?\z")
    validate one_of(:cover_type, ~w(image/webp image/png image/jpeg))
    validate byte_size(:cover, max: 1_000_000)
    validate byte_size(:markdown, max: 1_000_000)
  end

  identities do
    identity :unique_slug, [:slug]
  end

  attributes do
    uuid_primary_key :id
    attribute :slug, :string, allow_nil?: false, public?: true, constraints: [max_length: 63]

    attribute :title, :string,
      allow_nil?: false,
      public?: true,
      constraints: [min_length: 1, max_length: 240]

    attribute :description, :string,
      allow_nil?: false,
      public?: true,
      default: "",
      constraints: [allow_empty?: true]

    attribute :date, :date, allow_nil?: false, public?: true
    attribute :author, :string, allow_nil?: false, public?: true
    attribute :author_x, :string, allow_nil?: false, public?: true

    attribute :authors, {:array, :map},
      allow_nil?: false,
      public?: true,
      default: [],
      constraints: [
        max_length: 20,
        items: [
          fields: [
            name: [
              type: :string,
              allow_nil?: false,
              constraints: [min_length: 1, max_length: 120]
            ],
            x: [type: :string, allow_nil?: false, constraints: [min_length: 1, max_length: 128]]
          ]
        ]
      ]

    attribute :published_by, :integer

    attribute :markdown, :string,
      allow_nil?: false,
      public?: true,
      constraints: [trim?: false, min_length: 1]

    attribute :draft, :boolean, allow_nil?: false, default: false
    attribute :cover, :binary, allow_nil?: false
    attribute :cover_type, :string, allow_nil?: false
    attribute :cover_alt, :string, allow_nil?: false, public?: true
    timestamps()
  end

  postgres do
    table "blog_posts"
    repo(Regents.Repo)
  end
end
