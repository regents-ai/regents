defmodule Regents.Repo.Migrations.KeyfleetOwnershipSeq do
  @moduledoc """
  Numbers each fleet's ownership epochs as they are recorded, so a pass can
  name the keys it recorded.

  Generated with `mix ash.codegen ownership_seq`, then edited: epochs already
  recorded are numbered in chain order and each cursor's count is set to its
  fleet's number of epochs before the number is required, and the epoch
  guard is replaced in place, since its trigger depends on it.
  """

  use Ecto.Migration

  def up do
    alter table(:chain_cursors) do
      add(:ownership_seq, :bigint, null: false, default: 0)
    end

    create constraint(:chain_cursors, :chain_cursors_nonnegative_ownership_seq,
             check: """
               ownership_seq >= 0
             """
           )

    alter table(:key_attachments) do
      add(:record_seq, :bigint)
    end

    execute("""
    UPDATE keyfleet_app.key_attachments AS epoch
    SET record_seq = numbered.seq
    FROM (
      SELECT id,
             row_number() OVER (PARTITION BY fleet_id ORDER BY block_number, log_index) AS seq
      FROM keyfleet_app.key_attachments
    ) AS numbered
    WHERE epoch.id = numbered.id
    """)

    execute("""
    UPDATE keyfleet_app.chain_cursors AS cursor
    SET ownership_seq = counted.epochs
    FROM (
      SELECT fleet_id, count(*) AS epochs FROM keyfleet_app.key_attachments GROUP BY fleet_id
    ) AS counted
    WHERE cursor.fleet_id = counted.fleet_id
    """)

    alter table(:key_attachments) do
      modify(:record_seq, :bigint, null: false)
    end

    create unique_index(:key_attachments, [:fleet_id, :record_seq],
             name: "key_attachments_unique_record_seq_index"
           )

    create constraint(:key_attachments, :key_attachments_positive_record_seq,
             check: """
               record_seq > 0
             """
           )

    create index(:key_attachments, [:fleet_id, :block_number])

    execute("""
    CREATE OR REPLACE FUNCTION keyfleet_app.protect_key_epoch() RETURNS trigger LANGUAGE plpgsql AS $$
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
  end

  def down do
    execute("""
    CREATE OR REPLACE FUNCTION keyfleet_app.protect_key_epoch() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN
      IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'key ownership epochs cannot be deleted' USING ERRCODE = '23514';
      END IF;
      IF ROW(NEW.id, NEW.fleet_id, NEW.token_id, NEW.ownership_epoch, NEW.owner_wallet,
             NEW.block_number, NEW.block_hash, NEW.transaction_hash, NEW.log_index, NEW.observed_at)
         IS DISTINCT FROM
         ROW(OLD.id, OLD.fleet_id, OLD.token_id, OLD.ownership_epoch, OLD.owner_wallet,
             OLD.block_number, OLD.block_hash, OLD.transaction_hash, OLD.log_index, OLD.observed_at) THEN
        RAISE EXCEPTION 'key ownership projection fields are immutable' USING ERRCODE = '23514';
      END IF;
      RETURN NEW;
    END;
    $$;
    """)

    drop_if_exists(index(:key_attachments, [:fleet_id, :block_number]))

    drop_if_exists(constraint(:key_attachments, :key_attachments_positive_record_seq))

    drop_if_exists(
      unique_index(:key_attachments, [:fleet_id, :record_seq],
        name: "key_attachments_unique_record_seq_index"
      )
    )

    alter table(:key_attachments) do
      remove(:record_seq)
    end

    drop_if_exists(constraint(:chain_cursors, :chain_cursors_nonnegative_ownership_seq))

    alter table(:chain_cursors) do
      remove(:ownership_seq)
    end
  end
end
