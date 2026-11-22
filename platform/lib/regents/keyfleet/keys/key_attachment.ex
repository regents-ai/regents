defmodule Regents.Keyfleet.Keys.KeyAttachment do
  require Ash.Query

  @moduledoc """
  An immutable ownership epoch: who held a key, and from which transfer.
  `record_seq` is the fleet's count of epochs when it was recorded.
  """
  use Ash.Resource,
    domain: Regents.Keyfleet.Keys,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "key_attachments"
    schema("keyfleet_app")
    repo(Regents.Repo)
    migration_defaults(observed_at: "fragment(\"(now() AT TIME ZONE 'utc')\")")

    check_constraints do
      check_constraint(:token_id, "key_attachments_positive_token", check: "token_id > 0")

      check_constraint(:ownership_epoch, "key_attachments_positive_epoch",
        check: "ownership_epoch >= 1"
      )

      check_constraint(:block_number, "key_attachments_nonnegative_block",
        check: "block_number >= 0"
      )

      check_constraint(:log_index, "key_attachments_nonnegative_log", check: "log_index >= 0")

      check_constraint(:record_seq, "key_attachments_positive_record_seq",
        check: "record_seq > 0"
      )

      check_constraint(:owner_wallet, "key_attachments_owner_shape",
        check: "owner_wallet ~ '^0x[0-9a-f]{40}$'"
      )

      check_constraint(:block_hash, "key_attachments_block_hash_shape",
        check: "block_hash ~ '^0x[0-9a-f]{64}$'"
      )

      check_constraint(:transaction_hash, "key_attachments_transaction_hash_shape",
        check: "transaction_hash ~ '^0x[0-9a-f]{64}$'"
      )
    end

    custom_indexes do
      # The keys a wallet holds in a fleet, so the check whether someone may
      # post in, name or create a room, made on every such action, reads a few
      # entries.
      index([:fleet_id, :owner_wallet, :token_id])
      # What a stretch of blocks recorded, which every pass reads again.
      index([:fleet_id, :block_number])
      # The keys a wallet holds across every fleet.
      index([:owner_wallet])
    end

    custom_statements do
      statement :immutable_epochs_function do
        up("""
        CREATE FUNCTION keyfleet_app.protect_key_epoch() RETURNS trigger LANGUAGE plpgsql AS $$
        BEGIN
          IF TG_OP = 'DELETE' THEN
            RAISE EXCEPTION 'key ownership epochs cannot be deleted' USING ERRCODE = '23514';
          END IF;
          IF ROW(NEW.id, NEW.fleet_id, NEW.token_id, NEW.ownership_epoch, NEW.owner_wallet,
                 NEW.block_number, NEW.block_hash, NEW.transaction_hash, NEW.log_index, NEW.observed_at,
                 NEW.record_seq)
             IS DISTINCT FROM
             ROW(OLD.id, OLD.fleet_id, OLD.token_id, OLD.ownership_epoch, OLD.owner_wallet,
                 OLD.block_number, OLD.block_hash, OLD.transaction_hash, OLD.log_index, OLD.observed_at,
                 OLD.record_seq) THEN
            RAISE EXCEPTION 'key ownership projection fields are immutable' USING ERRCODE = '23514';
          END IF;
          RETURN NEW;
        END;
        $$;
        """)

        down("DROP FUNCTION keyfleet_app.protect_key_epoch();")
      end

      statement :immutable_epochs_trigger do
        up("""
        CREATE TRIGGER immutable_key_epochs BEFORE UPDATE OR DELETE ON keyfleet_app.key_attachments
        FOR EACH ROW EXECUTE FUNCTION keyfleet_app.protect_key_epoch();
        """)

        down("""
        DROP TRIGGER immutable_key_epochs ON keyfleet_app.key_attachments;
        """)
      end

      # Emptying the table is refused too; a row trigger never sees TRUNCATE.
      statement :untruncatable_epochs_function do
        up("""
        CREATE FUNCTION keyfleet_app.refuse_key_epoch_truncate() RETURNS trigger LANGUAGE plpgsql AS $$
        BEGIN
          RAISE EXCEPTION 'key ownership epochs cannot be deleted' USING ERRCODE = '23514';
        END;
        $$;
        """)

        down("DROP FUNCTION keyfleet_app.refuse_key_epoch_truncate();")
      end

      statement :untruncatable_epochs_trigger do
        up("""
        CREATE TRIGGER untruncatable_key_epochs BEFORE TRUNCATE ON keyfleet_app.key_attachments
        FOR EACH STATEMENT EXECUTE FUNCTION keyfleet_app.refuse_key_epoch_truncate();
        """)

        down("""
        DROP TRIGGER untruncatable_key_epochs ON keyfleet_app.key_attachments;
        """)
      end
    end
  end

  actions do
    create :record_epoch do
      public? false
      transaction? true

      accept [
        :fleet_id,
        :token_id,
        :ownership_epoch,
        :owner_wallet,
        :block_number,
        :block_hash,
        :transaction_hash,
        :log_index
      ]

      upsert? true
      upsert_identity :unique_key_epoch
      upsert_fields []
      upsert_condition expr(false)
      return_skipped_upsert? true

      change {Regents.Keyfleet.Chain.Changes.RecordOnce,
              identity: [:fleet_id, :token_id, :ownership_epoch], number: :ownership_seq}

      change Regents.Keyfleet.Notebooks.Changes.UpdateRoster

      # A dealt Key has its card from its mint, its first ownership record.
      change Regents.Keyfleet.Keys.Changes.QueuePicture,
        where: [attribute_equals(:ownership_epoch, 1)]
    end

    # The keys of the epochs recorded after the fleet's epoch number
    # `after_seq`, oldest first.
    read :recorded_since do
      public? false
      argument :fleet_id, :string, allow_nil?: false
      argument :after_seq, :integer, allow_nil?: false
      filter expr(fleet_id == ^arg(:fleet_id) and record_seq > ^arg(:after_seq))
      prepare build(select: [:token_id, :ownership_epoch], sort: [record_seq: :asc])
    end

    # The fleet's epochs recorded before its epoch number `before_seq` (from
    # the newest when nil), newest first, `limit` at most: each key sold (its
    # epoch 1, the mint) and each time one changed hands. `keys` and `wallet`
    # keep the epochs of those Keys or of that wallet taking a Key
    # (`Regents.Keyfleet.Preparations.DoneBy`).
    read :recorded_before do
      argument :fleet_id, :string, allow_nil?: false
      argument :before_seq, :integer, constraints: [min: 1, max: 9_223_372_036_854_775_807]
      argument :limit, :integer, allow_nil?: false, constraints: [min: 1, max: 100]
      argument :keys, {:array, :integer}
      argument :wallet, :string, constraints: [match: ~r/\A0x[0-9a-f]{40}\z/, trim?: false]
      filter expr(fleet_id == ^arg(:fleet_id))

      prepare {Regents.Keyfleet.Preparations.NewestFirst,
               sort: [record_seq: :desc], before: [:before_seq]}

      prepare {Regents.Keyfleet.Preparations.DoneBy, key: :token_id, wallet: :owner_wallet}

      prepare build(
                select: [
                  :fleet_id,
                  :token_id,
                  :ownership_epoch,
                  :transaction_hash,
                  :record_seq,
                  :observed_at
                ]
              )
    end

    # The fleet's epochs with these epoch numbers, each with the wallet its
    # key went to, so a page can show a run of transfers to one wallet as one.
    read :by_record_seq do
      argument :fleet_id, :string, allow_nil?: false
      argument :record_seqs, {:array, :integer}, allow_nil?: false

      filter expr(fleet_id == ^arg(:fleet_id) and record_seq in ^arg(:record_seqs))
      prepare build(select: [:fleet_id, :record_seq, :owner_wallet])
    end

    # The lowest-numbered key each of these wallets holds in the fleet right
    # now, one per wallet that holds any: who each of them is in the fleet.
    read :lowest_held do
      argument :fleet_id, :string, allow_nil?: false

      argument :owner_wallets, {:array, :string},
        allow_nil?: false,
        constraints: [max_length: 100]

      filter expr(
               fleet_id == ^arg(:fleet_id) and owner_wallet in ^arg(:owner_wallets) and
                 ownership_epoch == current_ownership_epoch
             )

      prepare build(
                select: [:fleet_id, :owner_wallet, :token_id],
                distinct: [:owner_wallet],
                distinct_sort: [owner_wallet: :asc, token_id: :asc]
              )
    end

    read :history do
      argument :fleet_id, :string, allow_nil?: false

      argument :token_id, :integer,
        allow_nil?: false,
        constraints: [min: 1, max: 9_223_372_036_854_775_807]

      filter expr(fleet_id == ^arg(:fleet_id) and token_id == ^arg(:token_id))

      prepare fn query, _context ->
        Ash.Query.before_action(query, fn query ->
          fleet_id = Ash.Query.get_argument(query, :fleet_id)
          token_id = Ash.Query.get_argument(query, :token_id)

          query
          |> Ash.Query.filter(fleet_id == ^fleet_id and token_id == ^token_id)
          |> Ash.Query.unset([:sort, :limit, :offset])
          |> Ash.Query.sort(ownership_epoch: :asc)
        end)
      end
    end

    read :current do
      argument :fleet_id, :string, allow_nil?: false

      argument :token_id, :integer,
        allow_nil?: false,
        constraints: [min: 1, max: 9_223_372_036_854_775_807]

      filter expr(fleet_id == ^arg(:fleet_id) and token_id == ^arg(:token_id))

      prepare fn query, _context ->
        Ash.Query.before_action(query, fn query ->
          fleet_id = Ash.Query.get_argument(query, :fleet_id)
          token_id = Ash.Query.get_argument(query, :token_id)

          query
          |> Ash.Query.filter(fleet_id == ^fleet_id and token_id == ^token_id)
          |> Ash.Query.unset([:sort, :offset])
          |> Ash.Query.sort(ownership_epoch: :desc)
          |> Ash.Query.limit(1)
        end)
      end

      get? true
    end

    # The fleet's keys with their owners today, unpaged, for counting the
    # addresses that hold them: all of them, or only those in `token_ids`.
    read :owned_in_fleet do
      argument :fleet_id, :string, allow_nil?: false
      argument :token_ids, {:array, :integer}

      filter expr(
               fleet_id == ^arg(:fleet_id) and ownership_epoch == current_ownership_epoch and
                 (is_nil(^arg(:token_ids)) or token_id in ^arg(:token_ids))
             )
    end

    # Every key the fleet has issued, each with its owner today, a page at a
    # time by key number: a fleet can issue tens of thousands.
    read :current_in_fleet do
      argument :fleet_id, :string, allow_nil?: false
      filter expr(fleet_id == ^arg(:fleet_id) and ownership_epoch == current_ownership_epoch)
      prepare build(sort: [token_id: :asc])
      pagination keyset?: true, required?: true, default_limit: 100, max_page_size: 100
    end

    # The fleet's keys that have a vote now: the ones a proposal opening now
    # would count.
    read :present_in_fleet do
      argument :fleet_id, :string, allow_nil?: false

      filter expr(
               fleet_id == ^arg(:fleet_id) and ownership_epoch == current_ownership_epoch and
                 present
             )
    end

    # The fleet's highest key number read so far. Keys are numbered from 1 in
    # the order they are sold and are never burned, so it is also how many
    # have sold.
    read :latest_in_fleet do
      public? false
      argument :fleet_id, :string, allow_nil?: false
      filter expr(fleet_id == ^arg(:fleet_id))
      prepare build(sort: [token_id: :desc], limit: 1, select: [:token_id])
      get? true
    end

    # The fleet's newest change of hands read so far: the latest sale or
    # transfer of any of its keys, by its place on the chain.
    read :newest_in_fleet do
      argument :fleet_id, :string, allow_nil?: false
      filter expr(fleet_id == ^arg(:fleet_id))
      prepare build(sort: [block_number: :desc, log_index: :desc], limit: 1, select: [:token_id])
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

    # Every key a person's wallets hold in this fleet right now, by number,
    # with the wallet holding each, for the key map and direct messages.
    read :held_in_fleet do
      argument :fleet_id, :string, allow_nil?: false
      argument :owner_wallets, {:array, :string}, allow_nil?: false

      filter expr(
               fleet_id == ^arg(:fleet_id) and owner_wallet in ^arg(:owner_wallets) and
                 ownership_epoch == current_ownership_epoch
             )

      prepare build(select: [:token_id, :ownership_epoch, :owner_wallet], sort: [token_id: :asc])
    end

    # Every key a person's wallets hold right now, in every fleet, by fleet
    # and number.
    read :held_everywhere do
      argument :owner_wallets, {:array, :string}, allow_nil?: false

      filter expr(
               owner_wallet in ^arg(:owner_wallets) and
                 ownership_epoch == current_ownership_epoch
             )

      prepare build(
                select: [:fleet_id, :token_id, :ownership_epoch, :owner_wallet],
                sort: [fleet_id: :asc, token_id: :asc]
              )
    end

    # Every record of one wallet holding any of some of the fleet's keys, then
    # or now.
    read :held_among do
      argument :fleet_id, :string, allow_nil?: false
      argument :owner_wallet, :string, allow_nil?: false
      argument :token_ids, {:array, :integer}, allow_nil?: false

      filter expr(
               fleet_id == ^arg(:fleet_id) and owner_wallet == ^arg(:owner_wallet) and
                 token_id in ^arg(:token_ids)
             )
    end

    # The lowest-numbered key a person's wallets hold in this fleet right now.
    # Keys rank by the order they were sold, so it is their highest-ranked key,
    # and it is who they are in the fleet: everything they write there is
    # written as it.
    read :identity_in_fleet do
      public? false
      argument :fleet_id, :string, allow_nil?: false
      argument :owner_wallets, {:array, :string}, allow_nil?: false

      filter expr(
               fleet_id == ^arg(:fleet_id) and owner_wallet in ^arg(:owner_wallets) and
                 ownership_epoch == current_ownership_epoch
             )

      prepare build(sort: [token_id: :asc], limit: 1)
      get? true
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action(:record_epoch) do
      authorize_if actor_attribute_equals(:role, :system)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :token_id, :integer,
      allow_nil?: false,
      public?: true,
      constraints: [min: 1, max: 9_223_372_036_854_775_807]

    attribute :ownership_epoch, :integer,
      allow_nil?: false,
      public?: true,
      constraints: [min: 1, max: 9_223_372_036_854_775_807]

    for field <- [:block_number, :log_index] do
      attribute field, :integer,
        allow_nil?: false,
        public?: true,
        constraints: [min: 0, max: 9_223_372_036_854_775_807]
    end

    attribute :owner_wallet, :string,
      allow_nil?: false,
      public?: true,
      constraints: [match: ~r/\A0x[0-9a-f]{40}\z/, trim?: false]

    for field <- [:block_hash, :transaction_hash] do
      attribute field, :string,
        allow_nil?: false,
        public?: true,
        constraints: [match: ~r/\A0x[0-9a-f]{64}\z/, trim?: false]
    end

    attribute :record_seq, :integer,
      allow_nil?: false,
      public?: true,
      constraints: [min: 1, max: 9_223_372_036_854_775_807]

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

  calculations do
    # The key's latest recorded owner, read as one scalar subquery because the
    # table has no scope-free read action to aggregate over.
    calculate :current_ownership_epoch,
              :integer,
              expr(
                fragment(
                  "(SELECT max(epoch.ownership_epoch) FROM keyfleet_app.key_attachments AS epoch WHERE epoch.fleet_id = ? AND epoch.token_id = ?)",
                  fleet_id,
                  token_id
                )
              )

    # Whether the key has a vote now, as the vote contract counts it
    # (`KeyfleetPresence.isActive`): its latest presence record, in chain
    # order, is a renewal or an automatic start whose 48 hours are running. A
    # newly sold key waiting for its automatic start is neither present nor
    # idle.
    calculate :present,
              :boolean,
              expr(
                fragment(
                  """
                  EXISTS (
                    SELECT 1 FROM (
                      SELECT presence.kind, presence.at
                      FROM keyfleet_app.key_presences AS presence
                      WHERE presence.fleet_id = ? AND presence.token_id = ?
                      ORDER BY presence.block_number DESC, presence.log_index DESC
                      LIMIT 1
                    ) AS last
                    WHERE last.kind IN ('present', 'scheduled')
                      AND last.at <= (now() AT TIME ZONE 'utc')
                      AND (now() AT TIME ZONE 'utc') < last.at + interval '48 hours'
                  )
                  """,
                  fleet_id,
                  token_id
                )
              )

    # Whether a present key has a day or less of its 48 hours left.
    calculate :expiring,
              :boolean,
              expr(
                fragment(
                  """
                  EXISTS (
                    SELECT 1 FROM (
                      SELECT presence.kind, presence.at
                      FROM keyfleet_app.key_presences AS presence
                      WHERE presence.fleet_id = ? AND presence.token_id = ?
                      ORDER BY presence.block_number DESC, presence.log_index DESC
                      LIMIT 1
                    ) AS last
                    WHERE last.kind IN ('present', 'scheduled')
                      AND (now() AT TIME ZONE 'utc') >= last.at + interval '24 hours'
                      AND (now() AT TIME ZONE 'utc') < last.at + interval '48 hours'
                  )
                  """,
                  fleet_id,
                  token_id
                )
              )

    # Whether the key's vote has lapsed: its latest presence record, in chain
    # order, is not a renewal or an automatic start whose 48 hours are still
    # running or still to come. A key whose 48 hours ran out, or that changed
    # hands, is idle until it is marked present again; a newly sold key
    # waiting for its automatic start is not.
    calculate :idle,
              :boolean,
              expr(
                fragment(
                  """
                  NOT EXISTS (
                    SELECT 1 FROM (
                      SELECT presence.kind, presence.at
                      FROM keyfleet_app.key_presences AS presence
                      WHERE presence.fleet_id = ? AND presence.token_id = ?
                      ORDER BY presence.block_number DESC, presence.log_index DESC
                      LIMIT 1
                    ) AS last
                    WHERE last.kind IN ('present', 'scheduled')
                      AND (now() AT TIME ZONE 'utc') < last.at + interval '48 hours'
                  )
                  """,
                  fleet_id,
                  token_id
                )
              )
  end

  identities do
    identity :unique_key_epoch, [:fleet_id, :token_id, :ownership_epoch]
    identity :unique_chain_event, [:transaction_hash, :log_index]
    identity :unique_record_seq, [:fleet_id, :record_seq]
  end
end
