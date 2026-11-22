defmodule Regents.Keyfleet.Keys.AgentVoting do
  @moduledoc """
  One `AgentVotingSet` log of a fleet's shard record: a key's owner letting
  the key's shards vote and propose for it, or stopping them, for as long as
  the key stays in the ownership epoch it names; a new owner starts with it
  on. Only the chain reader writes it, and nothing ever changes it. It is
  numbered with the fleet's shard records, in the order the chain made them.
  """
  use Ash.Resource,
    domain: Regents.Keyfleet.Keys,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  @max_bigint 9_223_372_036_854_775_807

  postgres do
    table "agent_voting_settings"
    schema("keyfleet_app")
    repo(Regents.Repo)
    migration_defaults(observed_at: "fragment(\"(now() AT TIME ZONE 'utc')\")")

    check_constraints do
      check_constraint(:token_id, "agent_voting_settings_positive_token", check: "token_id > 0")

      check_constraint(:ownership_epoch, "agent_voting_settings_positive_epoch",
        check: "ownership_epoch >= 1"
      )

      for field <- [:block_hash, :transaction_hash] do
        check_constraint(field, "agent_voting_settings_#{field}_shape",
          check: "#{field} ~ '^0x[0-9a-f]{64}$'"
        )
      end

      for field <- [:block_number, :log_index] do
        check_constraint(field, "agent_voting_settings_nonnegative_#{field}",
          check: "#{field} >= 0"
        )
      end

      check_constraint(:record_seq, "agent_voting_settings_positive_record_seq",
        check: "record_seq > 0"
      )
    end

    custom_indexes do
      # What the second reading of the last blocks compares with.
      index([:fleet_id, :block_number])
      # A key's latest setting.
      index([:fleet_id, :token_id, :record_seq])
    end

    # The same refusal every proposal record has, which names the table.
    custom_statements do
      statement :immutable_agent_voting_settings_trigger do
        up("""
        CREATE TRIGGER immutable_agent_voting_settings BEFORE UPDATE OR DELETE ON keyfleet_app.agent_voting_settings
        FOR EACH ROW EXECUTE FUNCTION keyfleet_app.refuse_proposal_record_change();
        """)

        down(
          "DROP TRIGGER immutable_agent_voting_settings ON keyfleet_app.agent_voting_settings;"
        )
      end

      statement :untruncatable_agent_voting_settings_trigger do
        up("""
        CREATE TRIGGER untruncatable_agent_voting_settings BEFORE TRUNCATE ON keyfleet_app.agent_voting_settings
        FOR EACH STATEMENT EXECUTE FUNCTION keyfleet_app.refuse_proposal_record_change();
        """)

        down(
          "DROP TRIGGER untruncatable_agent_voting_settings ON keyfleet_app.agent_voting_settings;"
        )
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
        :allowed,
        :ownership_epoch,
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
              identity: [:transaction_hash, :log_index], number: :shard_seq}
    end

    # A key's latest setting, whichever ownership it was made in.
    read :latest_of_key do
      public? false
      argument :fleet_id, :string, allow_nil?: false
      argument :token_id, :integer, allow_nil?: false, constraints: [min: 1, max: @max_bigint]
      filter expr(fleet_id == ^arg(:fleet_id) and token_id == ^arg(:token_id))
      prepare build(sort: [record_seq: :desc], limit: 1)
      get? true
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

    # The keys of the records made after the fleet's shard number
    # `after_seq`, oldest first.
    read :recorded_since do
      public? false
      argument :fleet_id, :string, allow_nil?: false
      argument :after_seq, :integer, allow_nil?: false
      filter expr(fleet_id == ^arg(:fleet_id) and record_seq > ^arg(:after_seq))
      prepare build(select: [:token_id], sort: [record_seq: :asc])
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

    attribute :allowed, :boolean, allow_nil?: false, public?: true

    attribute :ownership_epoch, :integer,
      allow_nil?: false,
      public?: true,
      constraints: [min: 1, max: @max_bigint]

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
