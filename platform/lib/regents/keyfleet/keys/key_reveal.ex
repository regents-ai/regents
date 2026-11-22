defmodule Regents.Keyfleet.Keys.KeyReveal do
  @moduledoc """
  One key's reveal, from its fleet's `KeyRevealed` log: the seed its traits
  are drawn from. Only a Key past its founding fleet's deck has one; a Key
  within the deck is dealt its card by number. A key is revealed once. Only
  the chain reader writes it, and nothing ever changes it.

  Read again, from the same block or another, with the same seed or another,
  the key's reveal is the one already recorded: it keeps the place, seed and
  number it was first recorded with. `record_seq` is the fleet's count of
  reveals when it was made.
  """
  use Ash.Resource,
    domain: Regents.Keyfleet.Keys,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  @max_bigint 9_223_372_036_854_775_807

  postgres do
    table "key_reveals"
    schema("keyfleet_app")
    repo(Regents.Repo)
    migration_defaults(observed_at: "fragment(\"(now() AT TIME ZONE 'utc')\")")

    check_constraints do
      check_constraint(:token_id, "key_reveals_positive_token", check: "token_id > 0")

      check_constraint(:request_id, "key_reveals_nonnegative_request_id",
        check: "request_id >= 0"
      )

      for field <- [:seed, :block_hash, :transaction_hash] do
        check_constraint(field, "key_reveals_#{field}_shape",
          check: "#{field} ~ '^0x[0-9a-f]{64}$'"
        )
      end

      for field <- [:block_number, :log_index] do
        check_constraint(field, "key_reveals_nonnegative_#{field}", check: "#{field} >= 0")
      end

      check_constraint(:record_seq, "key_reveals_positive_record_seq", check: "record_seq > 0")
    end

    custom_statements do
      # The same refusal every proposal record table uses; only the chain
      # reader inserts.
      statement :immutable_key_reveals_trigger do
        up("""
        CREATE TRIGGER immutable_key_reveals BEFORE UPDATE OR DELETE ON keyfleet_app.key_reveals
        FOR EACH ROW EXECUTE FUNCTION keyfleet_app.refuse_proposal_record_change();
        """)

        down("DROP TRIGGER immutable_key_reveals ON keyfleet_app.key_reveals;")
      end

      statement :untruncatable_key_reveals_trigger do
        up("""
        CREATE TRIGGER untruncatable_key_reveals BEFORE TRUNCATE ON keyfleet_app.key_reveals
        FOR EACH STATEMENT EXECUTE FUNCTION keyfleet_app.refuse_proposal_record_change();
        """)

        down("DROP TRIGGER untruncatable_key_reveals ON keyfleet_app.key_reveals;")
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
        :request_id,
        :seed,
        :block_number,
        :block_hash,
        :transaction_hash,
        :log_index
      ]

      upsert? true
      upsert_identity :unique_key_reveal
      upsert_fields []
      upsert_condition expr(false)
      return_skipped_upsert? true
      # A key is revealed once: the reveal saved first is kept.
      change {Regents.Keyfleet.Chain.Changes.RecordOnce,
              identity: [:fleet_id, :token_id], number: :reveal_seq}

      change Regents.Keyfleet.Keys.Changes.QueuePicture
    end

    # The keys revealed after the fleet's reveal number `after_seq`, oldest first.
    read :recorded_since do
      public? false
      argument :fleet_id, :string, allow_nil?: false
      argument :after_seq, :integer, allow_nil?: false
      filter expr(fleet_id == ^arg(:fleet_id) and record_seq > ^arg(:after_seq))
      prepare build(sort: [record_seq: :asc])
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

    # The reveals of these keys of the fleet, for the keys that have one.
    read :of_keys do
      argument :fleet_id, :string, allow_nil?: false
      argument :token_ids, {:array, :integer}, allow_nil?: false, constraints: [max_length: 100]
      filter expr(fleet_id == ^arg(:fleet_id) and token_id in ^arg(:token_ids))
      prepare build(select: [:token_id, :seed])
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

    # The coordinator's request the seed answered: any uint256.
    attribute :request_id, :decimal, allow_nil?: false, public?: true, constraints: [min: 0]

    for field <- [:seed, :block_hash, :transaction_hash] do
      attribute field, :string,
        allow_nil?: false,
        public?: true,
        constraints: [match: ~r/\A0x[0-9a-f]{64}\z/, trim?: false]
    end

    for field <- [:block_number, :log_index] do
      attribute field, :integer,
        allow_nil?: false,
        public?: true,
        constraints: [min: 0, max: @max_bigint]
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
    # A key is revealed once.
    identity :unique_key_reveal, [:fleet_id, :token_id]
    identity :unique_chain_event, [:transaction_hash, :log_index]
    identity :unique_record_seq, [:fleet_id, :record_seq]
  end
end
