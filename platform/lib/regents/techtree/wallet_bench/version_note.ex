defmodule Regents.Techtree.WalletBench.VersionNote do
  @moduledoc """
  Something odd the bench saw about one release of an agent or of a wallet
  tool, in plain words, beside the run that showed it when there is one.

  A note belongs to a release: `version` is written the way the bench's results
  show that release, so a note sits beside every result of it and of no other.
  It is an addendum for the reader and changes no result.

  Read only here: the operator who added a note is never read.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: Regents.Techtree.WalletBench,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  # Techtree's own area of the shared database, where techtree.sh's operators add
  # these rows; their migrations stay techtree.sh's.
  postgres do
    table "wallet_bench_version_notes"
    schema("techtree_app")
    repo(Regents.Repo)
    migrate?(false)
  end

  actions do
    read :listed do
      description "Every note, by agent or wallet, then release, oldest first."
      prepare build(sort: [kind: :asc, subject_id: :asc, version: :asc, inserted_at: :asc])
    end

    read :for_run do
      description "The notes on the agent release and the wallet release one run used."
      argument :harness_id, :string, allow_nil?: false
      argument :harness_version, :string
      argument :wallet_id, :string, allow_nil?: false
      argument :wallet_version, :string

      filter expr(
               (kind == :harness and subject_id == ^arg(:harness_id) and
                  version == ^arg(:harness_version)) or
                 (kind == :wallet and subject_id == ^arg(:wallet_id) and
                    version == ^arg(:wallet_version))
             )

      prepare build(sort: [kind: :asc, inserted_at: :asc])
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :kind, :atom do
      description "`harness`: an agent. `wallet`: a wallet tool."
      allow_nil? false
      public? true
      constraints one_of: [:harness, :wallet]
    end

    attribute :subject_id, :string, allow_nil?: false, public?: true

    attribute :version, :string do
      description "The release, written as the bench's results show it."
      allow_nil? false
      public? true
      constraints max_length: 64
    end

    attribute :text, :string do
      allow_nil? false
      public? true
      constraints max_length: 600
    end

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :attempt, Regents.Techtree.WalletBench.Attempt do
      description "The run that showed it, when one did."
      public? true
    end
  end
end
