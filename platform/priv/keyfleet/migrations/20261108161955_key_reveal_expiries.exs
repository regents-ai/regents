defmodule Regents.Repo.Migrations.KeyfleetKeyRevealExpiries do
  @moduledoc """
  The keys whose wait for their draw was ended (`RevealExpired`), as the chain
  reader records them (`Keyfleet.Keys.KeyRevealExpiry`). A new, empty table;
  nothing that exists changes.
  """

  use Ecto.Migration

  def up do
    create table(:key_reveal_expiries, primary_key: false) do
      add(:id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true)
      add(:token_id, :bigint, null: false)
      add(:block_hash, :text, null: false)
      add(:transaction_hash, :text, null: false)
      add(:block_number, :bigint, null: false)
      add(:log_index, :bigint, null: false)
      add(:record_seq, :bigint, null: false)

      add(:observed_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
      )

      add(
        :fleet_id,
        references(:fleets,
          column: :id,
          name: "key_reveal_expiries_fleet_id_fkey",
          type: :text,
          prefix: "keyfleet_app"
        ), null: false)
    end

    create unique_index(:key_reveal_expiries, [:transaction_hash, :log_index],
             name: "key_reveal_expiries_unique_chain_event_index"
           )

    create unique_index(:key_reveal_expiries, [:fleet_id, :token_id],
             name: "key_reveal_expiries_unique_key_reveal_expiry_index"
           )

    create unique_index(:key_reveal_expiries, [:fleet_id, :record_seq],
             name: "key_reveal_expiries_unique_record_seq_index"
           )

    create constraint(:key_reveal_expiries, :key_reveal_expiries_positive_token,
             check: """
               token_id > 0
             """
           )

    create constraint(:key_reveal_expiries, :key_reveal_expiries_block_hash_shape,
             check: """
               block_hash ~ '^0x[0-9a-f]{64}$'
             """
           )

    create constraint(:key_reveal_expiries, :key_reveal_expiries_transaction_hash_shape,
             check: """
               transaction_hash ~ '^0x[0-9a-f]{64}$'
             """
           )

    create constraint(:key_reveal_expiries, :key_reveal_expiries_nonnegative_block_number,
             check: """
               block_number >= 0
             """
           )

    create constraint(:key_reveal_expiries, :key_reveal_expiries_nonnegative_log_index,
             check: """
               log_index >= 0
             """
           )

    create constraint(:key_reveal_expiries, :key_reveal_expiries_positive_record_seq,
             check: """
               record_seq > 0
             """
           )

    execute("""
    CREATE TRIGGER immutable_key_reveal_expiries BEFORE UPDATE OR DELETE ON keyfleet_app.key_reveal_expiries
    FOR EACH ROW EXECUTE FUNCTION keyfleet_app.refuse_proposal_record_change();
    """)

    execute("""
    CREATE TRIGGER untruncatable_key_reveal_expiries BEFORE TRUNCATE ON keyfleet_app.key_reveal_expiries
    FOR EACH STATEMENT EXECUTE FUNCTION keyfleet_app.refuse_proposal_record_change();
    """)
  end

  def down do
    execute("""
    DROP TRIGGER untruncatable_key_reveal_expiries ON keyfleet_app.key_reveal_expiries;
    """)

    execute("""
    DROP TRIGGER immutable_key_reveal_expiries ON keyfleet_app.key_reveal_expiries;
    """)

    drop_if_exists(constraint(:key_reveal_expiries, :key_reveal_expiries_positive_record_seq))

    drop_if_exists(constraint(:key_reveal_expiries, :key_reveal_expiries_nonnegative_log_index))

    drop_if_exists(
      constraint(:key_reveal_expiries, :key_reveal_expiries_nonnegative_block_number)
    )

    drop_if_exists(constraint(:key_reveal_expiries, :key_reveal_expiries_transaction_hash_shape))

    drop_if_exists(constraint(:key_reveal_expiries, :key_reveal_expiries_block_hash_shape))

    drop_if_exists(constraint(:key_reveal_expiries, :key_reveal_expiries_positive_token))

    drop(constraint(:key_reveal_expiries, "key_reveal_expiries_fleet_id_fkey"))

    drop_if_exists(
      unique_index(:key_reveal_expiries, [:fleet_id, :record_seq],
        name: "key_reveal_expiries_unique_record_seq_index"
      )
    )

    drop_if_exists(
      unique_index(:key_reveal_expiries, [:fleet_id, :token_id],
        name: "key_reveal_expiries_unique_key_reveal_expiry_index"
      )
    )

    drop_if_exists(
      unique_index(:key_reveal_expiries, [:transaction_hash, :log_index],
        name: "key_reveal_expiries_unique_chain_event_index"
      )
    )

    drop(table(:key_reveal_expiries))
  end
end
