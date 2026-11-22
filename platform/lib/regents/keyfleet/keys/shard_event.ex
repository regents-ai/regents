defmodule Regents.Keyfleet.Keys.ShardEvent do
  @moduledoc """
  One `ShardIssued` or `ShardEnded` log of a fleet's shard record: a key's
  owner giving a wallet a shard of the key until `expires_at`, or the owner or
  the wallet ending it early. Only the chain reader writes it, and nothing
  ever changes it. `record_seq` is the fleet's count of shard records when it
  was recorded, which is the order the chain made them in.

  A wallet holds at most one shard of each key, and may hold shards of
  several keys, as the shards contract keeps them by key and wallet: each
  issue replaces what the wallet held of that key, and an end ends it. So a
  wallet's latest record of a key says where it stands, and a shard is active
  while that latest record is its issue, its time has not run out and its key
  has not changed hands since. Whether a shard is active is always worked
  out, never stored.
  """
  use Ash.Resource,
    domain: Regents.Keyfleet.Keys,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  @max_bigint 9_223_372_036_854_775_807
  @address ~r/\A0x[0-9a-f]{40}\z/
  @hash ~r/\A0x[0-9a-f]{64}\z/

  postgres do
    table "shard_events"
    schema("keyfleet_app")
    repo(Regents.Repo)
    migration_defaults(observed_at: "fragment(\"(now() AT TIME ZONE 'utc')\")")

    check_constraints do
      check_constraint(:kind, "shard_events_kind", check: "kind IN ('issued', 'ended')")

      # An issue carries its time and the key's ownership it lasts for; an end
      # carries who ended it.
      check_constraint(:kind, "shard_events_shape",
        check: """
        (kind = 'issued' AND expires_at IS NOT NULL AND ownership_epoch IS NOT NULL AND ended_by IS NULL)
        OR (kind = 'ended' AND expires_at IS NULL AND ownership_epoch IS NULL AND ended_by IS NOT NULL)
        """
      )

      check_constraint(:token_id, "shard_events_positive_token", check: "token_id > 0")

      check_constraint(:ownership_epoch, "shard_events_positive_epoch",
        check: "ownership_epoch >= 1"
      )

      for field <- [:wallet, :ended_by] do
        check_constraint(field, "shard_events_#{field}_shape",
          check: "#{field} ~ '^0x[0-9a-f]{40}$'"
        )
      end

      for field <- [:block_hash, :transaction_hash] do
        check_constraint(field, "shard_events_#{field}_shape",
          check: "#{field} ~ '^0x[0-9a-f]{64}$'"
        )
      end

      for field <- [:block_number, :log_index] do
        check_constraint(field, "shard_events_nonnegative_#{field}", check: "#{field} >= 0")
      end

      check_constraint(:record_seq, "shard_events_positive_record_seq", check: "record_seq > 0")
    end

    custom_indexes do
      # What the second reading of the last blocks compares with.
      index([:fleet_id, :block_number])
      # A wallet's latest record of a key, which says where it stands.
      index([:fleet_id, :token_id, :wallet, :record_seq])
      # A key's shards.
      index([:fleet_id, :token_id])
      # A wallet's shards in every fleet.
      index([:wallet])
    end

    # The same refusal every proposal record has, which names the table.
    custom_statements do
      statement :immutable_shard_events_trigger do
        up("""
        CREATE TRIGGER immutable_shard_events BEFORE UPDATE OR DELETE ON keyfleet_app.shard_events
        FOR EACH ROW EXECUTE FUNCTION keyfleet_app.refuse_proposal_record_change();
        """)

        down("DROP TRIGGER immutable_shard_events ON keyfleet_app.shard_events;")
      end

      statement :untruncatable_shard_events_trigger do
        up("""
        CREATE TRIGGER untruncatable_shard_events BEFORE TRUNCATE ON keyfleet_app.shard_events
        FOR EACH STATEMENT EXECUTE FUNCTION keyfleet_app.refuse_proposal_record_change();
        """)

        down("DROP TRIGGER untruncatable_shard_events ON keyfleet_app.shard_events;")
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
        :wallet,
        :expires_at,
        :ownership_epoch,
        :ended_by,
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

      change {Regents.Keyfleet.Notebooks.Changes.UpdateRoster, ends: :expires_at}
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

    # The fleet's records made before its shard number `before_seq` (from
    # the newest when nil), newest first, `limit` at most. `keys` and
    # `wallet` keep the shards of those Keys, and those lent to or ended by
    # that wallet (`Regents.Keyfleet.Preparations.DoneBy`).
    read :recorded_before do
      argument :fleet_id, :string, allow_nil?: false
      argument :before_seq, :integer, constraints: [min: 1, max: @max_bigint]
      argument :limit, :integer, allow_nil?: false, constraints: [min: 1, max: 100]
      argument :keys, {:array, :integer}
      argument :wallet, :string, constraints: [match: ~r/\A0x[0-9a-f]{40}\z/, trim?: false]
      filter expr(fleet_id == ^arg(:fleet_id))

      prepare {Regents.Keyfleet.Preparations.NewestFirst,
               sort: [record_seq: :desc], before: [:before_seq]}

      prepare {Regents.Keyfleet.Preparations.DoneBy, key: :token_id, wallet: [:wallet, :ended_by]}
    end

    # The active shard one wallet holds of a key, if it holds one.
    read :active_of_key_held_by do
      argument :fleet_id, :string, allow_nil?: false
      argument :token_id, :integer, allow_nil?: false
      argument :wallet, :string, allow_nil?: false

      filter expr(
               fleet_id == ^arg(:fleet_id) and token_id == ^arg(:token_id) and
                 wallet == ^arg(:wallet) and active?
             )

      get? true
    end

    # Every active shard one wallet holds, by fleet and then by key.
    read :active_held_by do
      argument :wallet, :string, allow_nil?: false
      filter expr(wallet == ^arg(:wallet) and active?)
      prepare build(sort: [fleet_id: :asc, token_id: :asc])
    end

    # Every active shard of some of the fleet's keys, each key's by the time
    # it was issued, soonest to run out first.
    read :active_of_keys do
      argument :fleet_id, :string, allow_nil?: false
      argument :token_ids, {:array, :integer}, allow_nil?: false, constraints: [max_length: 100]
      filter expr(fleet_id == ^arg(:fleet_id) and token_id in ^arg(:token_ids) and active?)
      prepare build(sort: [token_id: :asc, expires_at: :asc, record_seq: :asc])
    end

    # Every active shard in the fleet, each Key's by the time it ends, for the
    # agents' lines every open page of the fleet shares (`Regents.Keyfleet.Agents.Here`).
    read :active_in_fleet do
      argument :fleet_id, :string, allow_nil?: false
      filter expr(fleet_id == ^arg(:fleet_id) and active?)
      prepare build(sort: [token_id: :asc, expires_at: :asc, record_seq: :asc])
    end

    # The wallets a key's owner gave a shard of it, in any of the key's
    # ownerships that owner held, active or not: whoever wrote as the key
    # with one wrote for that owner.
    read :issued_by_owner do
      argument :fleet_id, :string, allow_nil?: false
      argument :token_id, :integer, allow_nil?: false
      argument :owner, :string, allow_nil?: false

      filter expr(
               fleet_id == ^arg(:fleet_id) and token_id == ^arg(:token_id) and kind == :issued and
                 fragment(
                   "? IN (SELECT held.ownership_epoch FROM keyfleet_app.key_attachments AS held WHERE held.fleet_id = ? AND held.token_id = ? AND held.owner_wallet = ?)",
                   ownership_epoch,
                   ^arg(:fleet_id),
                   ^arg(:token_id),
                   ^arg(:owner)
                 )
             )

      prepare build(select: [:wallet], distinct: [:wallet])
    end

    # The fleet's keys that have at least one active shard, by number, for
    # the key map.
    read :keys_with_shards do
      argument :fleet_id, :string, allow_nil?: false
      filter expr(fleet_id == ^arg(:fleet_id) and active?)

      prepare build(
                select: [:fleet_id, :token_id],
                distinct: [:token_id],
                sort: [token_id: :asc]
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

    attribute :kind, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: [:issued, :ended]]

    attribute :token_id, :integer,
      allow_nil?: false,
      public?: true,
      constraints: [min: 1, max: @max_bigint]

    attribute :wallet, :string,
      allow_nil?: false,
      public?: true,
      constraints: [match: @address, trim?: false]

    # When an issued shard stops being active, to the second.
    attribute :expires_at, :utc_datetime, public?: true

    # The key's ownership epoch an issued shard lasts for.
    attribute :ownership_epoch, :integer, public?: true, constraints: [min: 1, max: @max_bigint]

    # Who ended a shard early: the key's owner or the wallet itself.
    attribute :ended_by, :string, public?: true, constraints: [match: @address, trim?: false]

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
        constraints: [match: @hash, trim?: false]
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

    # The agent behind the wallet, once it has signed in and made a profile.
    has_one :agent_profile, Regents.Keyfleet.Agents.AgentProfile do
      source_attribute :wallet
      destination_attribute :wallet_address
      public? true
      read_action :public_profile
    end
  end

  calculations do
    # Whether this record is the wallet's latest of its key, read as one
    # scalar subquery because the table has no scope-free read to aggregate
    # over.
    calculate :latest?,
              :boolean,
              expr(
                fragment(
                  "NOT EXISTS (SELECT 1 FROM keyfleet_app.shard_events AS later WHERE later.fleet_id = ? AND later.token_id = ? AND later.wallet = ? AND later.record_seq > ?)",
                  fleet_id,
                  token_id,
                  wallet,
                  record_seq
                )
              )

    # The key's latest recorded owner's epoch.
    calculate :current_ownership_epoch,
              :integer,
              expr(
                fragment(
                  "(SELECT max(epoch.ownership_epoch) FROM keyfleet_app.key_attachments AS epoch WHERE epoch.fleet_id = ? AND epoch.token_id = ?)",
                  fleet_id,
                  token_id
                )
              )

    # An issued shard the wallet still holds: its latest record, with time
    # left, and its key not changed hands since.
    calculate :active?,
              :boolean,
              expr(
                kind == :issued and expires_at > now() and
                  ownership_epoch == current_ownership_epoch and latest?
              )
  end

  identities do
    identity :unique_chain_event, [:transaction_hash, :log_index]
    identity :unique_record_seq, [:fleet_id, :record_seq]
  end
end
