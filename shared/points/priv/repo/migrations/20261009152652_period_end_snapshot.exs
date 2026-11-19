defmodule RegentPoints.Repo.Migrations.PeriodEndSnapshot do
  @moduledoc """
  Updates resources based on their most recent snapshots.

  Generated with Ash; multi-command custom statements are wrapped in one DO
  block because Postgrex prepared statements accept one SQL command.
  """

  use Ecto.Migration

  def up do
    alter table(:period_bonuses, prefix: "regent_points") do
      add(:snapshot_id, :uuid)
    end

    execute("CREATE SCHEMA IF NOT EXISTS regent_points")

    create table(:period_snapshots, primary_key: false, prefix: "regent_points") do
      add(:id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true)
    end

    alter table(:period_bonuses, prefix: "regent_points") do
      modify(
        :snapshot_id,
        references(:period_snapshots,
          column: :id,
          name: "period_bonuses_snapshot_id_fkey",
          type: :uuid
        )
      )
    end

    alter table(:period_snapshots, prefix: "regent_points") do
      add(:program_id, :text, null: false)
      add(:period, :bigint, null: false)
      add(:starts_at, :utc_datetime_usec, null: false)
      add(:ends_at, :utc_datetime_usec, null: false)
      add(:block_number, :bigint, null: false)
      add(:block_hash, :text, null: false)
      add(:block_at, :utc_datetime_usec, null: false)
    end

    create unique_index(:period_snapshots, [:program_id, :period],
             name: "period_snapshots_program_period_index",
             prefix: "regent_points"
           )

    execute("CREATE SCHEMA IF NOT EXISTS regent_points")

    create table(:wallet_coverage, primary_key: false, prefix: "regent_points") do
      add(:id, :bigint, null: false, primary_key: true)
      add(:starts_at, :utc_datetime_usec, null: false)
    end

    execute("CREATE SCHEMA IF NOT EXISTS regent_points")

    create table(:wallet_snapshots, primary_key: false, prefix: "regent_points") do
      add(:id, :bigserial, null: false, primary_key: true)
      add(:account_id, :bigint, null: false)
      add(:wallet_addresses, {:array, :text}, null: false)
      add(:effective_at, :utc_datetime_usec, null: false)
    end

    create index(:wallet_snapshots, [:account_id, :effective_at, :id], prefix: "regent_points")

    execute("""
    DO $points_capture$
    BEGIN
    CREATE FUNCTION regent_points.verified_wallets(primary_wallet text, other_wallets text[])
    RETURNS text[] LANGUAGE sql IMMUTABLE AS $$
      SELECT COALESCE(array_agg(DISTINCT lower(wallet) ORDER BY lower(wallet)), ARRAY[]::text[])
      FROM unnest(COALESCE(other_wallets, ARRAY[]::text[]) || ARRAY[primary_wallet]) AS wallet
      WHERE wallet IS NOT NULL AND wallet <> '';
    $$;

    CREATE FUNCTION regent_points.capture_verified_wallets() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN
      IF TG_OP = 'INSERT' OR
         regent_points.verified_wallets(NEW.wallet_address, NEW.wallet_addresses)
         IS DISTINCT FROM regent_points.verified_wallets(OLD.wallet_address, OLD.wallet_addresses) THEN
        INSERT INTO regent_points.wallet_snapshots(account_id, wallet_addresses, effective_at)
        VALUES (NEW.id, regent_points.verified_wallets(NEW.wallet_address, NEW.wallet_addresses),
                clock_timestamp() AT TIME ZONE 'utc');
      END IF;
      RETURN NEW;
    END;
    $$;

    LOCK TABLE regent_names.platform_human_users IN SHARE ROW EXCLUSIVE MODE;
    INSERT INTO regent_points.wallet_coverage(id, starts_at)
    VALUES (1, clock_timestamp() AT TIME ZONE 'utc');
    INSERT INTO regent_points.wallet_snapshots(account_id, wallet_addresses, effective_at)
    SELECT id, regent_points.verified_wallets(wallet_address, wallet_addresses),
           (SELECT starts_at FROM regent_points.wallet_coverage WHERE id = 1)
    FROM regent_names.platform_human_users;

    CREATE TRIGGER points_verified_wallets
    AFTER INSERT OR UPDATE OF wallet_address, wallet_addresses ON regent_names.platform_human_users
    FOR EACH ROW EXECUTE FUNCTION regent_points.capture_verified_wallets();

    CREATE FUNCTION regent_points.refuse_snapshot_change() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN
      RAISE EXCEPTION 'regent_points.% rows are final', TG_TABLE_NAME;
    END;
    $$;
    CREATE TRIGGER wallet_snapshots_are_final BEFORE UPDATE OR DELETE ON regent_points.wallet_snapshots
    FOR EACH ROW EXECUTE FUNCTION regent_points.refuse_snapshot_change();
    CREATE TRIGGER wallet_coverage_is_final BEFORE UPDATE OR DELETE ON regent_points.wallet_coverage
    FOR EACH ROW EXECUTE FUNCTION regent_points.refuse_snapshot_change();
    CREATE TRIGGER period_snapshots_are_final BEFORE UPDATE OR DELETE ON regent_points.period_snapshots
    FOR EACH ROW EXECUTE FUNCTION regent_points.refuse_snapshot_change();
    END;
    $points_capture$;
    """)
  end

  def down do
    execute("""
    DO $points_uncapture$
    BEGIN
    DROP TRIGGER points_verified_wallets ON regent_names.platform_human_users;
    DROP FUNCTION regent_points.capture_verified_wallets();
    DROP FUNCTION regent_points.verified_wallets(text, text[]);
    DROP TRIGGER wallet_snapshots_are_final ON regent_points.wallet_snapshots;
    DROP TRIGGER wallet_coverage_is_final ON regent_points.wallet_coverage;
    DROP TRIGGER period_snapshots_are_final ON regent_points.period_snapshots;
    DROP FUNCTION regent_points.refuse_snapshot_change();
    END;
    $points_uncapture$;
    """)

    drop_if_exists(
      index(:wallet_snapshots, [:account_id, :effective_at, :id], prefix: "regent_points")
    )

    drop(table(:wallet_snapshots, prefix: "regent_points"))

    drop(table(:wallet_coverage, prefix: "regent_points"))

    drop_if_exists(
      unique_index(:period_snapshots, [:program_id, :period],
        name: "period_snapshots_program_period_index",
        prefix: "regent_points"
      )
    )

    alter table(:period_snapshots, prefix: "regent_points") do
      remove(:block_at)
      remove(:block_hash)
      remove(:block_number)
      remove(:ends_at)
      remove(:starts_at)
      remove(:period)
      remove(:program_id)
    end

    drop(constraint(:period_bonuses, "period_bonuses_snapshot_id_fkey", prefix: "regent_points"))

    alter table(:period_bonuses, prefix: "regent_points") do
      modify(:snapshot_id, :uuid)
    end

    drop(table(:period_snapshots, prefix: "regent_points"))

    alter table(:period_bonuses, prefix: "regent_points") do
      remove(:snapshot_id)
    end
  end
end
