defmodule Regents.PaperProDaily.Paper do
  @moduledoc """
  A paper on /paper-pro-daily: its title, its authors, the source paper, the
  shared ChatGPT answer, who wrote the answer, the answer's Markdown and its picture.

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
    :picture_alt
  ]

  actions do
    create :put do
      accept @fields
      upsert? true
      upsert_identity :paper_on_day
      upsert_fields (@fields -- [:date, :arxiv_url]) ++ [:updated_at]
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
                select: [:id, :date, :title, :arxiv_url, :chatgpt_url, :author, :answer]
              )
    end

    read :picture do
      argument :id, :uuid, allow_nil?: false
      get? true
      filter expr(id == ^arg(:id))
      prepare build(select: [:date, :picture, :picture_type])
    end
  end

  preparations do
    # Apply at read time to every surface, including export and direct picture URLs.
    # This is not a build-time date or a browser-side visibility rule.
    prepare Regents.PaperProDaily.Publication
  end

  policies do
    policy action(:put) do
      authorize_if Regents.Checks.SystemActor
    end

    # Anyone may read the papers admitted by the publication-date preparation.
    policy action_type(:read) do
      authorize_if always()
    end
  end

  validations do
    validate match(:arxiv_url, ~r{\Ahttps://[^\s/?#]+(?:[/?#][^\s]*)?\z})
    validate match(:chatgpt_url, ~r{\Ahttps://chatgpt\.com/share/[A-Za-z0-9\-]+\z})
    validate one_of(:picture_type, ~w(image/webp image/png image/jpeg))
    validate byte_size(:picture, max: 1_000_000)
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
    timestamps()
  end

  postgres do
    table "paper_pro_daily_papers"
    repo(Regents.Repo)
  end
end
