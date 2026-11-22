defmodule Regents.Repo.Migrations.KeyfleetKeeperSenderWallet do
  @moduledoc """
  Names the wallet that sent each keeper transaction, a lowercase address set
  once, and finds a wallet's waiting transactions by chain and nonce.
  Generated with `mix ash.codegen`, then changed by hand to replace the
  keeper_txs trigger function in place.
  """

  use Ecto.Migration

  def up do
    alter table(:keeper_txs) do
      add(:from_address, :text, null: false)
    end

    create constraint(:keeper_txs, :keeper_txs_from_address_shape,
             check: """
               from_address ~ '^0x[0-9a-f]{40}$'
             """
           )

    create index(:keeper_txs, [:chain_id, :from_address, :nonce], where: "status IS NULL")

    drop_if_exists(index(:keeper_txs, [:chain_id, :nonce]))

    # The keeper_txs triggers depend on this function, so it is replaced in
    # place, here and in `down/0`, rather than dropped and created again.
    execute("""
    CREATE OR REPLACE FUNCTION keyfleet_app.protect_keeper_tx() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN
      IF TG_OP <> 'UPDATE' THEN
        RAISE EXCEPTION 'keeper transactions cannot be deleted' USING ERRCODE = '23514';
      END IF;
      IF ROW(NEW.id, NEW.job, NEW.fleet_id, NEW.function, NEW.target, NEW.from_address,
             NEW.args, NEW.chain_id, NEW.nonce, NEW.tx_hash, NEW.replaces_tx_hash, NEW.max_fee,
             NEW.max_priority_fee, NEW.gas_limit, NEW.sent_at)
         IS DISTINCT FROM
         ROW(OLD.id, OLD.job, OLD.fleet_id, OLD.function, OLD.target, OLD.from_address,
             OLD.args, OLD.chain_id, OLD.nonce, OLD.tx_hash, OLD.replaces_tx_hash, OLD.max_fee,
             OLD.max_priority_fee, OLD.gas_limit, OLD.sent_at) THEN
        RAISE EXCEPTION 'what a keeper transaction sent cannot be changed' USING ERRCODE = '23514';
      END IF;
      IF OLD.status IS NOT NULL THEN
        RAISE EXCEPTION 'a settled keeper transaction cannot be changed' USING ERRCODE = '23514';
      END IF;
      RETURN NEW;
    END;
    $$;
    """)
  end

  def down do
    execute("""
    CREATE OR REPLACE FUNCTION keyfleet_app.protect_keeper_tx() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN
      IF TG_OP <> 'UPDATE' THEN
        RAISE EXCEPTION 'keeper transactions cannot be deleted' USING ERRCODE = '23514';
      END IF;
      IF ROW(NEW.id, NEW.job, NEW.fleet_id, NEW.function, NEW.target, NEW.args, NEW.chain_id,
             NEW.nonce, NEW.tx_hash, NEW.replaces_tx_hash, NEW.max_fee, NEW.max_priority_fee,
             NEW.gas_limit, NEW.sent_at)
         IS DISTINCT FROM
         ROW(OLD.id, OLD.job, OLD.fleet_id, OLD.function, OLD.target, OLD.args, OLD.chain_id,
             OLD.nonce, OLD.tx_hash, OLD.replaces_tx_hash, OLD.max_fee, OLD.max_priority_fee,
             OLD.gas_limit, OLD.sent_at) THEN
        RAISE EXCEPTION 'what a keeper transaction sent cannot be changed' USING ERRCODE = '23514';
      END IF;
      IF OLD.status IS NOT NULL THEN
        RAISE EXCEPTION 'a settled keeper transaction cannot be changed' USING ERRCODE = '23514';
      END IF;
      RETURN NEW;
    END;
    $$;
    """)

    create index(:keeper_txs, [:chain_id, :nonce], where: "status IS NULL")

    drop_if_exists(index(:keeper_txs, [:chain_id, :from_address, :nonce]))

    drop_if_exists(constraint(:keeper_txs, :keeper_txs_from_address_shape))

    alter table(:keeper_txs) do
      remove(:from_address)
    end
  end
end
