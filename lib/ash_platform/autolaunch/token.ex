defmodule AshPlatform.Autolaunch.Token do
  alias AshPlatform.Autolaunch.{SubjectIdentity, TreasurySecurity}

  use Ash.Resource,
    otp_app: :ash_platform,
    domain: AshPlatform.Autolaunch,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  require Ash.Query

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 100, trim?: true
    end

    attribute :symbol, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 16, match: ~r/\A[A-Z0-9]+\z/
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
      constraints SubjectIdentity.constraints()
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

    attribute :treasury_address, :string do
      public? true
      constraints min_length: 42, max_length: 42, match: ~r/\A0x[0-9a-fA-F]{40}\z/
    end

    timestamps()
  end

  relationships do
    belongs_to :auction, AshPlatform.Autolaunch.Auction do
      allow_nil? false
      attribute_public? true
    end

    belongs_to :treasury_security_report,
               AshPlatform.Autolaunch.TreasurySecurityReport do
      attribute_public? true
    end
  end

  actions do
    read :read do
      primary? true
    end

    read :list_public do
      prepare build(sort: [graduated_at: :desc, id: :asc], load: [:treasury_security_report])
    end

    read :top_public do
      filter expr(not is_nil(top_rank))

      prepare build(
                sort: [top_rank: :asc, id: :asc],
                limit: 12,
                load: [:treasury_security_report]
              )
    end

    read :recently_graduated_public do
      prepare build(
                sort: [graduated_at: :desc, id: :asc],
                limit: 12,
                load: [:treasury_security_report, :auction]
              )
    end

    read :graduated_launchpad do
      argument :query, :string,
        allow_nil?: false,
        constraints: [allow_empty?: true, max_length: 80]

      prepare fn query, _context -> launchpad_query(query, 8) end
    end

    read :explore_launchpad do
      argument :query, :string,
        allow_nil?: false,
        constraints: [allow_empty?: true, max_length: 80]

      prepare fn query, _context -> launchpad_query(query, 24) end
    end

    read :for_subject do
      argument :subject_id, :string,
        allow_nil?: false,
        constraints: SubjectIdentity.constraints()

      filter expr(subject_id == ^arg(:subject_id))

      prepare build(
                sort: [graduated_at: :desc, id: :asc],
                limit: 25,
                load: [:treasury_security_report]
              )
    end

    read :public_by_id do
      get? true
      argument :id, :uuid, allow_nil?: false
      filter expr(id == ^arg(:id))
      prepare build(load: [:treasury_security_report, :auction])
    end

    read :latest_price_for_subject do
      get? true

      argument :subject_id, :string,
        allow_nil?: false,
        constraints: SubjectIdentity.constraints()

      filter expr(subject_id == ^arg(:subject_id) and not is_nil(price_quote))
      prepare build(sort: [price_updated_at: :desc, id: :desc], limit: 1)
    end

    create :import_public do
      accept [
        :auction_id,
        :subject_id,
        :name,
        :symbol,
        :summary,
        :graduated_at,
        :top_rank,
        :treasury_security_report_id
      ]

      change fn changeset, _context -> TreasurySecurity.associate_token_report(changeset) end
    end

    create :project_lab do
      accept [
        :auction_id,
        :subject_id,
        :name,
        :symbol,
        :summary,
        :graduated_at,
        :top_rank,
        :treasury_address
      ]

      upsert? true
      upsert_identity :unique_auction

      upsert_fields [
        :subject_id,
        :name,
        :symbol,
        :summary,
        :graduated_at,
        :treasury_address
      ]
    end

    update :set_price_snapshot do
      require_atomic? false
      accept [:price_quote, :price_source, :price_updated_at]
    end
  end

  policies do
    policy action([
             :read,
             :list_public,
             :top_public,
             :recently_graduated_public,
             :graduated_launchpad,
             :explore_launchpad,
             :for_subject,
             :public_by_id,
             :latest_price_for_subject
           ]) do
      authorize_if always()
    end

    policy action([:import_public, :project_lab, :set_price_snapshot]) do
      authorize_if AshPlatform.Checks.SystemActor
    end
  end

  identities do
    identity :unique_auction, [:auction_id]
  end

  postgres do
    table "tokens"
    schema("autolaunch")
    repo(AshPlatform.Repo)
  end

  defp launchpad_query(query, limit) do
    term = query.arguments.query |> String.trim() |> String.downcase()
    pattern = literal_search_pattern(term)

    query
    |> launchpad_search_filter(term, pattern)
    |> Ash.Query.sort(graduated_at: :desc, id: :asc)
    |> Ash.Query.limit(limit)
    |> Ash.Query.load([:treasury_security_report, :auction])
  end

  defp launchpad_search_filter(query, "", _pattern), do: query

  defp launchpad_search_filter(query, _term, pattern) do
    Ash.Query.filter(
      query,
      ilike(name, ^pattern) or
        ilike(symbol, ^pattern) or
        ilike(summary, ^pattern) or
        ilike(auction.title, ^pattern) or
        ilike(auction.summary, ^pattern) or
        ilike(auction.auction_address, ^pattern) or
        exists(
          [:auction, :creator_x_connections],
          not is_nil(verified_at) and
            (ilike(username, ^pattern) or ilike(display_name, ^pattern))
        )
    )
  end

  defp literal_search_pattern(term) do
    "%" <>
      (term
       |> String.replace("\\", "\\\\")
       |> String.replace("%", "\\%")
       |> String.replace("_", "\\_")) <> "%"
  end
end
