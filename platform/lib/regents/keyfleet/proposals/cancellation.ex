defmodule Regents.Keyfleet.Proposals.Cancellation do
  @moduledoc """
  One `ProposalCancelled` log: a recorded proposal cancelled by whoever could
  vote its author key, which happens at most once. Only the chain reader
  writes it, and nothing ever changes it.
  """
  use Ash.Resource,
    domain: Regents.Keyfleet.Proposals,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  @max_bigint 9_223_372_036_854_775_807

  postgres do
    table "proposal_cancellations"
    schema("keyfleet_app")
    repo(Regents.Repo)
    migration_defaults(observed_at: "fragment(\"(now() AT TIME ZONE 'utc')\")")

    check_constraints do
      check_constraint(:cancelled_by, "proposal_cancellations_cancelled_by_shape",
        check: "cancelled_by ~ '^0x[0-9a-f]{40}$'"
      )

      for field <- [:block_hash, :transaction_hash] do
        check_constraint(field, "proposal_cancellations_#{field}_shape",
          check: "#{field} ~ '^0x[0-9a-f]{64}$'"
        )
      end

      for field <- [:block_number, :log_index] do
        check_constraint(field, "proposal_cancellations_nonnegative_#{field}",
          check: "#{field} >= 0"
        )
      end

      check_constraint(:record_seq, "proposal_cancellations_positive_record_seq",
        check: "record_seq > 0"
      )
    end

    custom_indexes do
      # What the second reading of the last blocks compares with.
      index([:fleet_id, :block_number])
    end

    custom_statements do
      statement :immutable_proposal_cancellations_trigger do
        up("""
        CREATE TRIGGER immutable_proposal_cancellations BEFORE UPDATE OR DELETE ON keyfleet_app.proposal_cancellations
        FOR EACH ROW EXECUTE FUNCTION keyfleet_app.refuse_proposal_record_change();
        """)

        down(
          "DROP TRIGGER immutable_proposal_cancellations ON keyfleet_app.proposal_cancellations;"
        )
      end

      statement :untruncatable_proposal_cancellations_trigger do
        up("""
        CREATE TRIGGER untruncatable_proposal_cancellations BEFORE TRUNCATE ON keyfleet_app.proposal_cancellations
        FOR EACH STATEMENT EXECUTE FUNCTION keyfleet_app.refuse_proposal_record_change();
        """)

        down(
          "DROP TRIGGER untruncatable_proposal_cancellations ON keyfleet_app.proposal_cancellations;"
        )
      end
    end
  end

  actions do
    defaults [:read]

    create :record do
      public? false
      accept [:fleet_id, :cancelled_by, :block_number, :block_hash, :transaction_hash, :log_index]

      argument :proposal_number, :integer,
        allow_nil?: false,
        constraints: [min: 1, max: @max_bigint]

      upsert? true
      upsert_identity :unique_cancellation
      upsert_fields []
      upsert_condition expr(false)
      return_skipped_upsert? true
      change Regents.Keyfleet.Proposals.Changes.FindProposal

      change {Regents.Keyfleet.Chain.Changes.RecordOnce,
              identity: [:proposal_id], number: :proposal_seq}
    end

    # What was recorded from a stretch of the fleet's blocks, and from the
    # `transactions` named wherever it was recorded, so a reading of the
    # stretch can be checked against it.
    read :recorded_in_blocks do
      public? false
      argument :fleet_id, :string, allow_nil?: false
      argument :from_block, :integer, allow_nil?: false
      argument :to_block, :integer, allow_nil?: false
      argument :transactions, {:array, :string}, default: []

      filter expr(
               fleet_id == ^arg(:fleet_id) and
                 ((block_number >= ^arg(:from_block) and block_number <= ^arg(:to_block)) or
                    transaction_hash in ^arg(:transactions))
             )

      prepare build(load: [:proposal_number])
    end

    # The fleet's cancellations recorded before its record number
    # `before_seq` (from the newest when nil), newest first, `limit` at most,
    # each with the number of the proposal cancelled. `keys` and `wallet`
    # keep the proposals those Keys made and those that wallet cancelled
    # (`Regents.Keyfleet.Preparations.DoneBy`).
    read :recorded_before do
      argument :fleet_id, :string, allow_nil?: false
      argument :before_seq, :integer, constraints: [min: 1, max: @max_bigint]
      argument :limit, :integer, allow_nil?: false, constraints: [min: 1, max: 100]
      argument :keys, {:array, :integer}
      argument :wallet, :string, constraints: [match: ~r/\A0x[0-9a-f]{40}\z/, trim?: false]
      filter expr(fleet_id == ^arg(:fleet_id))

      prepare {Regents.Keyfleet.Preparations.NewestFirst,
               sort: [record_seq: :desc], before: [:before_seq]}

      prepare {Regents.Keyfleet.Preparations.DoneBy, key: :author_key, wallet: :cancelled_by}

      prepare build(
                select: [:id, :fleet_id, :proposal_id, :record_seq, :observed_at],
                load: [:proposal_number]
              )
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action(:record) do
      authorize_if actor_attribute_equals(:role, :system)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :cancelled_by, :string,
      allow_nil?: false,
      public?: true,
      constraints: [match: ~r/\A0x[0-9a-f]{40}\z/, trim?: false]

    for field <- [:block_number, :log_index] do
      attribute field, :integer,
        allow_nil?: false,
        public?: true,
        constraints: [min: 0, max: @max_bigint]
    end

    for field <- [:block_hash, :transaction_hash] do
      attribute field, :string,
        allow_nil?: false,
        public?: true,
        constraints: [match: ~r/\A0x[0-9a-f]{64}\z/, trim?: false]
    end

    attribute :record_seq, :integer,
      allow_nil?: false,
      public?: true,
      constraints: [min: 1, max: @max_bigint]

    attribute :observed_at, :utc_datetime_usec,
      allow_nil?: false,
      generated?: true,
      writable?: false,
      public?: true
  end

  relationships do
    belongs_to :fleet, Regents.Keyfleet.Fleets.Fleet do
      attribute_type :string
      allow_nil? false
      public? true
    end

    belongs_to :proposal, Regents.Keyfleet.Proposals.Proposal do
      allow_nil? false
      public? true
    end
  end

  calculations do
    calculate :proposal_number, :integer, expr(proposal.number), public?: true
    calculate :author_key, :integer, expr(proposal.author_key), public?: true
  end

  identities do
    # A proposal is cancelled once.
    identity :unique_cancellation, [:proposal_id]
    identity :unique_chain_event, [:transaction_hash, :log_index]
    identity :unique_record_seq, [:fleet_id, :record_seq]
  end
end
