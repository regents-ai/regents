defmodule Regents.PaperProDaily.Paper do
  @moduledoc """
  A paper on /paper-pro-daily: its title, its authors, the source paper, the
  shared ChatGPT answer, who wrote the answer, the answer's Markdown, its picture
  and the one to three topics it is filed under (`Regents.PaperProDaily.Tag`).

  A day may have several papers; putting the same source paper on the same day
  again replaces it. Only a release command writes papers
  (`Regents.Release.put_paper/2`). Future days may be saved early; public reads
  include a paper once its date begins in UTC.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.PaperProDaily,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  @fields [
    :date,
    :title,
    :authors,
    :arxiv_url,
    :chatgpt_url,
    :author,
    :answer,
    :picture,
    :picture_type,
    :picture_alt,
    :tags
  ]

  actions do
    create :put do
      accept @fields
      upsert? true
      upsert_identity :paper_on_day
      upsert_fields (@fields -- [:date, :arxiv_url]) ++ [:updated_at]
    end

    # Files a paper under other topics without touching the rest of it.
    update :tag do
      accept [:tags]
      # Papers have no primary read to upgrade an atomic update with.
      require_atomic? false
    end

    # Files many published papers at once, all or none: paper ids to their tags.
    action :tag_papers, :integer do
      argument :tags, :map, allow_nil?: false
      transaction? true

      run fn input, context ->
        opts = Ash.Context.to_opts(context)

        Enum.each(input.arguments.tags, fn {id, tags} ->
          case Regents.PaperProDaily.get_paper!(id, opts) do
            nil -> raise ArgumentError, "#{id}: no published paper has this id"
            paper -> Regents.PaperProDaily.tag_paper!(paper, %{tags: tags}, opts)
          end
        end)

        {:ok, map_size(input.arguments.tags)}
      end
    end

    # The given days' papers, newest day first and each day's papers in the order
    # they were saved, without the pictures, which `:picture` serves one at a time.
    read :list do
      argument :dates, {:array, :date}, allow_nil?: false
      filter expr(date in ^arg(:dates))
      prepare build(sort: [date: :desc, inserted_at: :asc], deselect: [:picture])
    end

    read :export do
      prepare build(
                sort: [date: :desc, inserted_at: :asc],
                select: [:id, :date, :title, :arxiv_url, :chatgpt_url, :author, :answer, :tags]
              )
    end

    read :outline do
      prepare build(sort: [date: :desc, inserted_at: :asc], select: [:id, :date, :title, :tags])
    end

    read :picture do
      argument :id, :uuid, allow_nil?: false
      get? true
      filter expr(id == ^arg(:id))
      prepare build(select: [:date, :picture, :picture_type])
    end

    read :feed do
      prepare build(
                sort: [date: :desc, inserted_at: :asc, id: :asc],
                select: [
                  :id,
                  :date,
                  :title,
                  :authors,
                  :arxiv_url,
                  :chatgpt_url,
                  :author,
                  :picture_alt,
                  :tags,
                  :updated_at
                ]
              )

      pagination do
        required? true
        keyset? true
        default_limit 10
        max_page_size 10
      end
    end

    read :details do
      argument :id, :uuid, allow_nil?: false
      get? true
      filter expr(id == ^arg(:id))
      prepare build(deselect: [:picture])
    end

    read :by_anchor do
      argument :anchor, :string, allow_nil?: false
      get? true
      filter expr(fragment("left(?::text, 8)", id) == ^arg(:anchor))
      prepare build(deselect: [:picture], sort: [date: :desc], limit: 1)
    end
  end

  preparations do
    # Apply at read time to every surface, including export and direct picture URLs.
    # This is not a build-time date or a browser-side visibility rule.
    prepare Regents.PaperProDaily.Publication
  end

  policies do
    policy action([:put, :tag, :tag_papers]) do
      authorize_if Regents.Checks.SystemActor
    end

    # Anyone may read the papers admitted by the publication-date preparation.
    policy action_type(:read) do
      authorize_if always()
    end
  end

  # The saved paper's own rules; tagging changes only its tags.
  validations do
    validate match(:arxiv_url, ~r{\Ahttps://[^\s/?#]+(?:[/?#][^\s]*)?\z}), on: :create

    validate match(
               :chatgpt_url,
               ~r{\Ahttps://chatgpt\.com/(?:share/[A-Za-z0-9\-]+|s/t_[A-Za-z0-9]+)\z}
             ),
             on: :create

    validate one_of(:picture_type, ~w(image/webp image/png image/jpeg)), on: :create
    validate byte_size(:picture, max: 1_000_000), on: :create
  end

  identities do
    identity :paper_on_day, [:date, :arxiv_url]
  end

  attributes do
    uuid_primary_key :id
    attribute :date, :date, allow_nil?: false, public?: true
    attribute :title, :string, allow_nil?: false, public?: true
    attribute :authors, {:array, :string}, allow_nil?: false, default: [], public?: true
    attribute :arxiv_url, :string, allow_nil?: false, public?: true
    attribute :chatgpt_url, :string, allow_nil?: false, public?: true
    attribute :author, :string, allow_nil?: false, public?: true

    attribute :answer, :string,
      allow_nil?: false,
      public?: true,
      constraints: [trim?: false]

    attribute :picture, :binary, allow_nil?: false
    attribute :picture_type, :string, allow_nil?: false
    attribute :picture_alt, :string, allow_nil?: false, public?: true

    attribute :tags, {:array, Regents.PaperProDaily.Tag},
      allow_nil?: false,
      default: [],
      public?: true,
      constraints: [min_length: 1, max_length: 3, nil_items?: false, remove_nil_items?: false]

    timestamps()
  end

  postgres do
    table "paper_pro_daily_papers"
    repo(Regents.Repo)
  end
end
