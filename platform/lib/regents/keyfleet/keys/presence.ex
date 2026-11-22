defmodule Regents.Keyfleet.Keys.Presence do
  @moduledoc """
  One `PresenceScheduled`, `Present` or `PresenceCleared` log of a fleet's
  vote contract: a newly sold Key whose automatic presence starts at `at`, 2
  days after its sale, and lasts 48 hours (`:scheduled`); a Key renewed at
  `at`, present for 48 hours under the ownership epoch it was renewed in
  (`:present`); or a Key that changed hands and stopped being present
  (`:cleared`). A Key still waiting for its automatic start keeps it when it
  changes hands. Only the chain reader writes it, and nothing ever changes
  it.

  A Key is renewed whenever it proposes, votes, cancels or is renewed on its
  own. Whether a key was present when a proposal opened is worked out from
  these records (`Regents.Keyfleet.Proposals.Calculations.LateKeys`), never stored.
  """
  use Ash.Resource,
    domain: Regents.Keyfleet.Keys,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  @max_bigint 9_223_372_036_854_775_807

  postgres do
    table "key_presences"
    schema("keyfleet_app")
    repo(Regents.Repo)
    migration_defaults(observed_at: "fragment(\"(now() AT TIME ZONE 'utc')\")")

    check_constraints do
      # A renewal carries its time and the ownership it belongs to, an
      # automatic start only its time, and a change of hands neither.
      check_constraint(:kind, "key_presences_shape",
        check: """
        (kind = 'present' AND at IS NOT NULL AND ownership_epoch >= 1)
        OR (kind = 'scheduled' AND at IS NOT NULL AND ownership_epoch IS NULL)
        OR (kind = 'cleared' AND at IS NULL AND ownership_epoch IS NULL)
        """
      )

      check_constraint(:token_id, "key_presences_positive_token", check: "token_id > 0")

      for field <- [:block_hash, :transaction_hash] do
        check_constraint(field, "key_presences_#{field}_shape",
          check: "#{field} ~ '^0x[0-9a-f]{64}$'"
        )
      end

      for field <- [:block_number, :log_index] do
        check_constraint(field, "key_presences_nonnegative_#{field}", check: "#{field} >= 0")
      end
    end

    custom_indexes do
      # What the second reading of the last blocks compares with.
      index([:fleet_id, :block_number])
      # A key's last record before a proposal opened.
      index([:fleet_id, :token_id, :block_number, :log_index])
    end

    # The same refusal every proposal record has, which names the table.
    custom_statements do
      statement :immutable_key_presences_trigger do
        up("""
        CREATE TRIGGER immutable_key_presences BEFORE UPDATE OR DELETE ON keyfleet_app.key_presences
        FOR EACH ROW EXECUTE FUNCTION keyfleet_app.refuse_proposal_record_change();
        """)

        down("DROP TRIGGER immutable_key_presences ON keyfleet_app.key_presences;")
      end

      statement :untruncatable_key_presences_trigger do
        up("""
        CREATE TRIGGER untruncatable_key_presences BEFORE TRUNCATE ON keyfleet_app.key_presences
        FOR EACH STATEMENT EXECUTE FUNCTION keyfleet_app.refuse_proposal_record_change();
        """)

        down("DROP TRIGGER untruncatable_key_presences ON keyfleet_app.key_presences;")
      end
    end
  end

  actions do
    defaults [:read]

    create :record do
      public? false

      accept [
        :fleet_id,
        :kind,
        :token_id,
        :at,
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
              identity: [:transaction_hash, :log_index]}
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

    # The Keys marked present on their own, newest first, from just before
    # the log at `before_block` and `before_log` (from the newest when nil),
    # `limit` at most: each renewal whose transaction proposed, voted and
    # cancelled nothing, as those renew their Keys too. `keys` keeps those
    # Keys' renewals (`Regents.Keyfleet.Preparations.DoneBy`); a renewal names no
    # wallet.
    read :marked_before do
      argument :fleet_id, :string, allow_nil?: false
      argument :before_block, :integer, constraints: [min: 0, max: @max_bigint]
      argument :before_log, :integer, constraints: [min: 0, max: @max_bigint]
      argument :limit, :integer, allow_nil?: false, constraints: [min: 1, max: 100]
      argument :keys, {:array, :integer}
      argument :wallet, :string, constraints: [match: ~r/\A0x[0-9a-f]{40}\z/, trim?: false]

      filter expr(
               fleet_id == ^arg(:fleet_id) and kind == :present and
                 fragment(
                   "NOT EXISTS (SELECT 1 FROM keyfleet_app.proposal_votes AS v WHERE v.transaction_hash = ?) AND NOT EXISTS (SELECT 1 FROM keyfleet_app.proposals AS p WHERE p.transaction_hash = ?) AND NOT EXISTS (SELECT 1 FROM keyfleet_app.proposal_cancellations AS c WHERE c.transaction_hash = ?)",
                   transaction_hash,
                   transaction_hash,
                   transaction_hash
                 )
             )

      prepare {Regents.Keyfleet.Preparations.NewestFirst,
               sort: [block_number: :desc, log_index: :desc], before: [:before_block, :before_log]}

      prepare {Regents.Keyfleet.Preparations.DoneBy, key: :token_id}
      prepare build(select: [:id, :fleet_id, :token_id, :block_number, :log_index, :observed_at])
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

    attribute :kind, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: [:scheduled, :present, :cleared]]

    attribute :token_id, :integer,
      allow_nil?: false,
      public?: true,
      constraints: [min: 1, max: @max_bigint]

    attribute :at, :utc_datetime, public?: true
    attribute :ownership_epoch, :integer, public?: true, constraints: [min: 1, max: @max_bigint]

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
  end
end
