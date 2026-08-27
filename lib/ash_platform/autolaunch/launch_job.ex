defmodule AshPlatform.Autolaunch.LaunchJob do
  alias AshPlatform.Autolaunch.LaunchIdentity

  use Ash.Resource,
    otp_app: :ash_platform,
    domain: AshPlatform.Autolaunch,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  attributes do
    uuid_primary_key :id, public?: false

    attribute :job_id, :string do
      allow_nil? false
      public? true
      constraints LaunchIdentity.constraints()
    end

    attribute :status, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 100, trim?: true
    end

    attribute :step, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 100, trim?: true
    end

    attribute :agent_id, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 128, trim?: true
    end

    attribute :agent_name, :string do
      public? true
      constraints max_length: 160, trim?: true
    end

    attribute :token_name, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 100, trim?: true
    end

    attribute :token_symbol, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 16, match: ~r/\A[A-Z0-9]+\z/
    end

    attribute :chain_id, :integer do
      allow_nil? false
      public? true
      constraints min: 1
    end

    attribute :agent_safe_address, :string do
      public? true
      constraints max_length: 128, trim?: true
    end

    attribute :auction_address, :string do
      public? true
      constraints max_length: 128, trim?: true
    end

    attribute :token_address, :string do
      public? true
      constraints max_length: 128, trim?: true
    end

    attribute :hook_address, :string do
      public? true
      constraints max_length: 128, trim?: true
    end

    attribute :revenue_share_splitter_address, :string do
      public? true
      constraints max_length: 128, trim?: true
    end

    attribute :started_at, :utc_datetime_usec do
      public? true
    end

    attribute :finished_at, :utc_datetime_usec do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :auction, AshPlatform.Autolaunch.Auction do
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
      prepare build(sort: [inserted_at: :desc, id: :asc], load: [:treasury_security_report])
    end

    read :public_by_id do
      get? true

      argument :job_id, :string,
        allow_nil?: false,
        constraints: LaunchIdentity.constraints()

      filter expr(job_id == ^arg(:job_id))
      prepare build(load: [:treasury_security_report])
    end

    create :import_public do
      accept [
        :job_id,
        :status,
        :step,
        :agent_id,
        :agent_name,
        :token_name,
        :token_symbol,
        :chain_id,
        :auction_id,
        :agent_safe_address,
        :auction_address,
        :token_address,
        :hook_address,
        :revenue_share_splitter_address,
        :started_at,
        :finished_at,
        :treasury_security_report_id
      ]
    end
  end

  policies do
    policy action([:read, :list_public, :public_by_id]) do
      authorize_if always()
    end

    policy action(:import_public) do
      authorize_if AshPlatform.Checks.SystemActor
    end
  end

  identities do
    identity :unique_job_id, [:job_id]
  end

  postgres do
    table "launch_jobs"
    schema("autolaunch")
    repo(AshPlatform.Repo)
  end
end
