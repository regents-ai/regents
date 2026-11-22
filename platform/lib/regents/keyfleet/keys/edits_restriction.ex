defmodule Regents.Keyfleet.Keys.EditsRestriction do
  @moduledoc """
  One `EditsRestrictionSet` log of a fleet's vote contract: a proposal carried
  out that restricted a key's workspace edits, or allowed them again; its
  execution is logged in the same transaction. Only the
  chain reader writes it, and nothing ever changes it. It is numbered with the
  fleet's proposal records, in the order the chain made them.

  A key's latest record says whether its edits are restricted now; a key with
  none is not. While they are, neither the key's owner nor its shards may
  write the workspace, though they can still read it and chat.
  """
  use Ash.Resource,
    domain: Regents.Keyfleet.Keys,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  @max_bigint 9_223_372_036_854_775_807

  postgres do
    table "edits_restrictions"
    schema("keyfleet_app")
    repo(Regents.Repo)
    migration_defaults(observed_at: "fragment(\"(now() AT TIME ZONE 'utc')\")")

    check_constraints do
      check_constraint(:token_id, "edits_restrictions_positive_token", check: "token_id > 0")

      for field <- [:block_hash, :transaction_hash] do
        check_constraint(field, "edits_restrictions_#{field}_shape",
          check: "#{field} ~ '^0x[0-9a-f]{64}$'"
        )
      end

      for field <- [:block_number, :log_index] do
        check_constraint(field, "edits_restrictions_nonnegative_#{field}", check: "#{field} >= 0")
      end

      check_constraint(:record_seq, "edits_restrictions_positive_record_seq",
        check: "record_seq > 0"
      )
    end

    custom_indexes do
      # What the second reading of the last blocks compares with.
      index([:fleet_id, :block_number])
      # A key's latest record.
      index([:fleet_id, :token_id, :record_seq])
    end

    # The same refusal every proposal record has, which names the table.
    custom_statements do
      statement :immutable_edits_restrictions_trigger do
        up("""
        CREATE TRIGGER immutable_edits_restrictions BEFORE UPDATE OR DELETE ON keyfleet_app.edits_restrictions
        FOR EACH ROW EXECUTE FUNCTION keyfleet_app.refuse_proposal_record_change();
        """)

        down("DROP TRIGGER immutable_edits_restrictions ON keyfleet_app.edits_restrictions;")
      end

      statement :untruncatable_edits_restrictions_trigger do
        up("""
        CREATE TRIGGER untruncatable_edits_restrictions BEFORE TRUNCATE ON keyfleet_app.edits_restrictions
        FOR EACH STATEMENT EXECUTE FUNCTION keyfleet_app.refuse_proposal_record_change();
        """)

        down("DROP TRIGGER untruncatable_edits_restrictions ON keyfleet_app.edits_restrictions;")
      end
    end
  end

  actions do
    defaults [:read]

    create :record do
      public? false

      accept [
        :fleet_id,
        :token_id,
        :restricted,
        :block_number,
        :block_hash,
        :transaction_hash,
        :log_index
      ]

      upsert? true
      upsert_identity :unique_chain_event
      upsert_fields []
      upsert_condition expr(false)
      return_skipped_upsert? true

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
    end

    # The keys of the records made after the fleet's proposal record number
    # `after_seq`, oldest first.
    read :recorded_since do
      public? false
      argument :fleet_id, :string, allow_nil?: false
      argument :after_seq, :integer, allow_nil?: false
      filter expr(fleet_id == ^arg(:fleet_id) and record_seq > ^arg(:after_seq))
      prepare build(select: [:token_id], sort: [record_seq: :asc])
    end

    # The latest record for each of some of the fleet's keys, one per key
    # that has any.
    read :latest_for_keys do
      argument :fleet_id, :string, allow_nil?: false
      argument :token_ids, {:array, :integer}, allow_nil?: false, constraints: [max_length: 100]
      filter expr(fleet_id == ^arg(:fleet_id) and token_id in ^arg(:token_ids))

      prepare build(
                distinct: [:token_id],
                distinct_sort: [token_id: :asc, record_seq: :desc]
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

    attribute :token_id, :integer,
      allow_nil?: false,
      public?: true,
      constraints: [min: 1, max: @max_bigint]

    attribute :restricted, :boolean, allow_nil?: false, public?: true

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
  end

  identities do
    identity :unique_chain_event, [:transaction_hash, :log_index]
    identity :unique_record_seq, [:fleet_id, :record_seq]
  end
end
