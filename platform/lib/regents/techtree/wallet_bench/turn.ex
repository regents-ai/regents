defmodule Regents.Techtree.WalletBench.Turn do
  @moduledoc """
  One prompt sent to the harness in an attempt, and what came of it.

  `state` moves forward one step per job on techtree.sh's bench: `queued`,
  `running`, `finished` (the turn's folder is back, blanked and stored as
  evidence) and `judged`. A turn that cannot go on is `failed`, and its attempt
  stops. An attempt has at most one turn per test.

  Read only here: only the columns the pages read are attributes.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Techtree.WalletBench,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Regents.Techtree.WalletBench.Catalog

  # Techtree's own area of the shared database, where techtree.sh's bench writes
  # these rows; their migrations stay techtree.sh's.
  postgres do
    table "wallet_bench_turns"
    schema("techtree_app")
    repo(Regents.Repo)
    migrate?(false)
  end

  actions do
    defaults [:read]
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :test, :atom do
      allow_nil? false
      public? true
      constraints one_of: Catalog.tests()
    end

    attribute :state, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:queued, :running, :finished, :judged, :failed]
    end

    attribute :prompt, :string do
      description "The prompt as sent, word for word."
      allow_nil? false
      public? true
      constraints trim?: false, allow_empty?: false
    end

    attribute :started_at, :utc_datetime_usec, public?: true
    attribute :ended_at, :utc_datetime_usec, public?: true
    attribute :wall_seconds, :decimal, public?: true

    attribute :model_spend_usd, :decimal,
      public?: true,
      description: "What the tested model's calls in this turn cost, as the translator counted."

    attribute :evidence, :map do
      description "Each stored file of the turn's folder, blanked: its sha256 and size."
      public? true
    end

    attribute :checks, :map do
      description "The bench's own checks for the judge, such as the Base check."
      public? true
    end

    attribute :judgment, :map do
      description "The judge's ruling: outcome, C1–C9, summary and reasoning."
      public? true
    end

    attribute :judge_cost_usd, :decimal do
      description "What every ruling on the turn cost together."
      public? true
    end

    attribute :failure, :string, public?: true, description: "Why the turn failed."

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :attempt, Regents.Techtree.WalletBench.Attempt do
      allow_nil? false
      public? true
    end
  end
end
