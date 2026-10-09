defmodule Regents.PaperProDaily.Paper do
  @moduledoc """
  One day's paper on /paper-pro-daily: its title, the source paper, the shared
  ChatGPT answer, who wrote the answer, the answer's Markdown and its picture.

  One paper a day; putting a paper on a day that has one replaces it. Only a
  release command writes papers (`Regents.Release.put_paper/2`); anyone reads them.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.PaperProDaily,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  @fields [
    :date,
    :title,
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
      upsert_identity :one_a_day
      upsert_fields List.delete(@fields, :date) ++ [:updated_at]
    end

    # Newest first, without the pictures, which `:picture` serves one at a time.
    read :list do
      prepare build(sort: [date: :desc], deselect: [:picture])
      pagination offset?: true, default_limit: 6, countable: false, required?: true
    end

    read :export do
      prepare build(
                sort: [date: :desc],
                select: [:date, :title, :arxiv_url, :chatgpt_url, :author, :answer]
              )
    end

    read :picture do
      argument :date, :date, allow_nil?: false
      get? true
      filter expr(date == ^arg(:date))
      prepare build(select: [:date, :picture, :picture_type])
    end
  end

  policies do
    policy action(:put) do
      authorize_if Regents.Checks.SystemActor
    end

    # Every paper is public the moment it is written.
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
    identity :one_a_day, [:date]
  end

  attributes do
    uuid_primary_key :id
    attribute :date, :date, allow_nil?: false, public?: true
    attribute :title, :string, allow_nil?: false, public?: true
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
