defmodule Regents.Keyfleet.Proposals.Vote do
  @moduledoc """
  One `BallotCast` log: a set of keys voted yes, no or abstain on a recorded
  proposal, one vote per key, each replacing any earlier vote of the key on
  it. Only the chain reader writes it, and nothing ever changes it.
  """
  use Ash.Resource,
    domain: Regents.Keyfleet.Proposals,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  @max_bigint 9_223_372_036_854_775_807

  postgres do
    table "proposal_votes"
    schema("keyfleet_app")
    repo(Regents.Repo)
    migration_defaults(observed_at: "fragment(\"(now() AT TIME ZONE 'utc')\")")

    check_constraints do
      check_constraint(:voter, "proposal_votes_voter_shape", check: "voter ~ '^0x[0-9a-f]{40}$'")

      check_constraint(:choice, "proposal_votes_choice",
        check: "choice IN ('yes', 'no', 'abstain')"
      )

      check_constraint(:token_ids, "proposal_votes_some_keys",
        check: "cardinality(token_ids) > 0 AND 0 < ALL (token_ids)"
      )

      for field <- [:block_hash, :transaction_hash] do
        check_constraint(field, "proposal_votes_#{field}_shape",
          check: "#{field} ~ '^0x[0-9a-f]{64}$'"
        )
      end

      for field <- [:block_number, :log_index] do
        check_constraint(field, "proposal_votes_nonnegative_#{field}", check: "#{field} >= 0")
      end

      check_constraint(:record_seq, "proposal_votes_positive_record_seq", check: "record_seq > 0")
    end

    custom_indexes do
      index([:proposal_id, :record_seq])
      # What the second reading of the last blocks compares with.
      index([:fleet_id, :block_number])
      # The votes a key has been used in.
      index([:token_ids], using: "GIN")
      # The votes a wallet has cast in a fleet.
      index([:fleet_id, :voter])
    end

    custom_statements do
      statement :immutable_proposal_votes_trigger do
        up("""
        CREATE TRIGGER immutable_proposal_votes BEFORE UPDATE OR DELETE ON keyfleet_app.proposal_votes
        FOR EACH ROW EXECUTE FUNCTION keyfleet_app.refuse_proposal_record_change();
        """)

        down("DROP TRIGGER immutable_proposal_votes ON keyfleet_app.proposal_votes;")
      end

      statement :untruncatable_proposal_votes_trigger do
        up("""
        CREATE TRIGGER untruncatable_proposal_votes BEFORE TRUNCATE ON keyfleet_app.proposal_votes
        FOR EACH STATEMENT EXECUTE FUNCTION keyfleet_app.refuse_proposal_record_change();
        """)

        down("DROP TRIGGER untruncatable_proposal_votes ON keyfleet_app.proposal_votes;")
      end
    end
  end

  actions do
    defaults [:read]

    create :record do
      public? false

      accept [
        :fleet_id,
        :voter,
        :choice,
        :token_ids,
        :block_number,
        :block_hash,
        :transaction_hash,
        :log_index
      ]

      argument :proposal_number, :integer,
        allow_nil?: false,
        constraints: [min: 1, max: @max_bigint]

      upsert? true
      upsert_identity :unique_chain_event
      upsert_fields []
      upsert_condition expr(false)
      return_skipped_upsert? true
      change Regents.Keyfleet.Proposals.Changes.FindProposal

      change {Regents.Keyfleet.Chain.Changes.RecordOnce,
              identity: [:transaction_hash, :log_index], number: :proposal_seq}
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

    # The fleet's votes recorded before its record number `before_seq` (from
    # the newest when nil), newest first, `limit` at most, each with the
    # number of the proposal it was cast on. `keys` and `wallet` keep the
    # votes cast with those Keys or by that wallet
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

      prepare {Regents.Keyfleet.Preparations.DoneBy, keys: :token_ids, wallet: :voter}

      prepare build(
                select: [
                  :id,
                  :fleet_id,
                  :proposal_id,
                  :choice,
                  :token_ids,
                  :record_seq,
                  :observed_at
                ],
                load: [:proposal_number]
              )
    end

    # Every vote in the fleet cast with key `token_id`.
    read :with_key do
      argument :fleet_id, :string, allow_nil?: false
      argument :token_id, :integer, allow_nil?: false, constraints: [min: 1, max: @max_bigint]

      filter expr(
               fleet_id == ^arg(:fleet_id) and
                 fragment("? @> ARRAY[?]::bigint[]", token_ids, ^arg(:token_id))
             )
    end

    # Every vote `voter` has cast in the fleet.
    read :by_voter do
      argument :fleet_id, :string, allow_nil?: false
      argument :voter, :string, allow_nil?: false
      filter expr(fleet_id == ^arg(:fleet_id) and voter == ^arg(:voter))
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

    attribute :voter, :string,
      allow_nil?: false,
      public?: true,
      constraints: [match: ~r/\A0x[0-9a-f]{40}\z/, trim?: false]

    attribute :choice, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: [:yes, :no, :abstain]]

    attribute :token_ids, {:array, :integer},
      allow_nil?: false,
      public?: true,
      constraints: [min_length: 1, items: [min: 1, max: @max_bigint]]

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

  calculations do
    # Every key is one vote.
    calculate :key_count, :integer, expr(length(token_ids)), public?: true

    calculate :proposal_number, :integer, expr(proposal.number), public?: true
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

  identities do
    identity :unique_chain_event, [:transaction_hash, :log_index]
    identity :unique_record_seq, [:fleet_id, :record_seq]
  end
end
