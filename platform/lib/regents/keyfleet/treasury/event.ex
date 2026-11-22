defmodule Regents.Keyfleet.Treasury.Event do
  @moduledoc """
  One money log of a fleet's contracts, of the kind `kind`, as
  `Regents.Keyfleet.Chain.MoneyLog` reads it: the fleet contract forwarding an asset
  to its treasury or sending the protocol share; the treasury paying,
  advancing, getting an advance back, running the daily split and splitting
  each bound asset, changing the split rate, admitting OUSD, binding the
  launch token or approving or revoking a hash it signs; the reward ledger
  settling a key's rewards to its holder or paying out credit; and the REGENT
  buyer every fleet shares turning a piece of its USDC into REGENT. Only
  the chain reader writes it, and nothing ever changes it.

  Each kind carries exactly its own fields and leaves the rest empty.
  Amounts are in the asset's own units, any uint256; ETH is the zero
  address. `record_seq` is the fleet's count of proposal and money records
  when it was made.
  """
  use Ash.Resource,
    domain: Regents.Keyfleet.Treasury,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Regents.Keyfleet.Chain.MoneyLog

  @max_bigint 9_223_372_036_854_775_807
  @addresses [:asset, :account, :by]
  @numbers [
    :share,
    :amount,
    :balance,
    :per_key,
    :keys,
    :bps,
    :advance_id,
    :outstanding,
    :threshold,
    :launch_id,
    :usdc_in,
    :weth_mid,
    :regent_out
  ]
  @hashes [:purpose_hash, :signed_hash]

  # Each kind's fields set and every other field empty.
  @shapes (for {kind, fields} <- Enum.sort(MoneyLog.fields_of_kinds()) do
             empty = MoneyLog.fields() -- fields

             "(kind = '#{kind}' AND num_nonnulls(#{Enum.join(fields, ", ")}) = #{length(fields)}" <>
               if(empty == [],
                 do: ")",
                 else: " AND num_nulls(#{Enum.join(empty, ", ")}) = #{length(empty)})"
               )
           end)

  postgres do
    table "treasury_events"
    schema("keyfleet_app")
    repo(Regents.Repo)
    migration_defaults(observed_at: "fragment(\"(now() AT TIME ZONE 'utc')\")")

    check_constraints do
      check_constraint(:kind, "treasury_events_shape", check: Enum.join(@shapes, "\nOR "))

      for field <- @addresses do
        check_constraint(field, "treasury_events_#{field}_shape",
          check: "#{field} ~ '^0x[0-9a-f]{40}$'"
        )
      end

      for field <- @hashes ++ [:block_hash, :transaction_hash] do
        check_constraint(field, "treasury_events_#{field}_shape",
          check: "#{field} ~ '^0x[0-9a-f]{64}$'"
        )
      end

      for field <- @numbers ++ [:block_number, :log_index] do
        check_constraint(field, "treasury_events_nonnegative_#{field}", check: "#{field} >= 0")
      end

      check_constraint(:token_id, "treasury_events_positive_token_id", check: "token_id > 0")

      check_constraint(:record_seq, "treasury_events_positive_record_seq",
        check: "record_seq > 0"
      )
    end

    custom_indexes do
      # What the second reading of the last blocks compares with.
      index([:fleet_id, :block_number])
      # A fleet's latest records of a kind.
      index([:fleet_id, :kind, :record_seq])
    end

    # The same refusal every proposal record has, which names the table.
    custom_statements do
      statement :immutable_treasury_events_trigger do
        up("""
        CREATE TRIGGER immutable_treasury_events BEFORE UPDATE OR DELETE ON keyfleet_app.treasury_events
        FOR EACH ROW EXECUTE FUNCTION keyfleet_app.refuse_proposal_record_change();
        """)

        down("DROP TRIGGER immutable_treasury_events ON keyfleet_app.treasury_events;")
      end

      statement :untruncatable_treasury_events_trigger do
        up("""
        CREATE TRIGGER untruncatable_treasury_events BEFORE TRUNCATE ON keyfleet_app.treasury_events
        FOR EACH STATEMENT EXECUTE FUNCTION keyfleet_app.refuse_proposal_record_change();
        """)

        down("DROP TRIGGER untruncatable_treasury_events ON keyfleet_app.treasury_events;")
      end
    end
  end

  actions do
    defaults [:read]

    create :record do
      public? false

      accept [:fleet_id, :kind | MoneyLog.fields()] ++
               [:block_number, :block_hash, :transaction_hash, :log_index]

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

    # The fleet's latest records of the kinds named, newest first, `limit`
    # at most.
    read :latest_of_kinds do
      argument :fleet_id, :string, allow_nil?: false
      argument :kinds, {:array, :atom}, allow_nil?: false
      argument :limit, :integer, allow_nil?: false, constraints: [min: 1, max: 100]
      filter expr(fleet_id == ^arg(:fleet_id) and kind in ^arg(:kinds))

      prepare fn query, _context ->
        query
        |> Ash.Query.sort(record_seq: :desc)
        |> Ash.Query.limit(Ash.Query.get_argument(query, :limit))
      end
    end

    # The fleet's records of the kinds named recorded before its record
    # number `before_seq` (from the newest when nil), newest first, `limit`
    # at most. `keys` and `wallet` keep the records of those Keys and those
    # paying or made by that wallet (`Regents.Keyfleet.Preparations.DoneBy`).
    read :of_kinds_before do
      argument :fleet_id, :string, allow_nil?: false
      argument :kinds, {:array, :atom}, allow_nil?: false
      argument :before_seq, :integer, constraints: [min: 1, max: @max_bigint]
      argument :limit, :integer, allow_nil?: false, constraints: [min: 1, max: 100]
      argument :keys, {:array, :integer}
      argument :wallet, :string, constraints: [match: ~r/\A0x[0-9a-f]{40}\z/, trim?: false]
      filter expr(fleet_id == ^arg(:fleet_id) and kind in ^arg(:kinds))

      prepare {Regents.Keyfleet.Preparations.NewestFirst,
               sort: [record_seq: :desc], before: [:before_seq]}

      prepare {Regents.Keyfleet.Preparations.DoneBy, key: :token_id, wallet: [:account, :by]}
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
      constraints: [one_of: MoneyLog.kinds()]

    for field <- @addresses do
      attribute field, :string,
        public?: true,
        constraints: [match: ~r/\A0x[0-9a-f]{40}\z/, trim?: false]
    end

    for field <- @numbers do
      attribute field, :decimal, public?: true, constraints: [min: 0]
    end

    attribute :voted, :boolean, public?: true

    for field <- @hashes do
      attribute field, :string,
        public?: true,
        constraints: [match: ~r/\A0x[0-9a-f]{64}\z/, trim?: false]
    end

    attribute :token_id, :integer, public?: true, constraints: [min: 1, max: @max_bigint]

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
