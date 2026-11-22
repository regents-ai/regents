defmodule Regents.Autolaunch.LaunchJob do
  @moduledoc """
  One agent launch job: the agent, the token it launched and the contracts its
  launch made.

  The table and its rows as autolaunch.sh keeps them; nothing here reads or
  writes them yet.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Autolaunch,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  # A job id occupies one public URL segment, the identifier format the public
  # route catalog accepts.
  @job_id_shape ~r/\A[a-zA-Z0-9][a-zA-Z0-9._:-]{0,127}\z/

  postgres do
    table "launch_jobs"
    schema("autolaunch_app")
    repo(Regents.Repo)
  end

  attributes do
    uuid_primary_key :id, public?: false

    attribute :job_id, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 128, trim?: false, match: @job_id_shape
    end

    # Never advanced past what launch discovery first wrote, and read by
    # nothing; these four columns are dropped by the next release, once no
    # machine of the release before still reads them.
    attribute :status, :string do
      select_by_default? false
      constraints min_length: 1, max_length: 100, trim?: true
    end

    attribute :step, :string do
      select_by_default? false
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

    attribute :treasury_address, :string do
      public? true
      constraints min_length: 42, max_length: 42, match: ~r/\A0x[0-9a-fA-F]{40}\z/
    end

    attribute :started_at, :utc_datetime_usec do
      select_by_default? false
    end

    attribute :finished_at, :utc_datetime_usec do
      select_by_default? false
    end

    timestamps()
  end

  relationships do
    belongs_to :auction, Regents.Autolaunch.Auction do
      attribute_public? true
    end

    belongs_to :treasury_security_report,
               Regents.Autolaunch.TreasurySecurityReport do
      attribute_public? true
    end
  end

  identities do
    identity :unique_job_id, [:job_id]
  end

  # No action is carried yet, so every action is refused; each comes with its own
  # policies.
  policies do
    policy always() do
      forbid_if always()
    end
  end
end
