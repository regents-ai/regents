defmodule RegentAgents.Migrations.PairingHistory do
  use Ecto.Migration

  def up do
    # The migration transaction holds this through backfill and trigger setup,
    # so an existing site's pairing/unpairing cannot escape the archive.
    execute("LOCK TABLE regent_agents.paired_agents IN SHARE ROW EXCLUSIVE MODE")

    # Keep paired_agents as the active-only table understood by deployed sites.
    # Database triggers retain episodes even when an older site unpairs by DELETE.
    create table(:pairing_history, prefix: "regent_agents", primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:privy_user_id, :text, null: false)
      add(:wallet, :text, null: false)
      add(:name, :text, null: false)
      add(:harness, :text, null: false)
      add(:paired_at, :utc_datetime_usec, null: false)
      add(:last_contact_at, :utc_datetime_usec, null: false)
      add(:human_id, :text)
      add(:same_person_agent_count, :bigint)
      add(:revoked_at, :utc_datetime_usec)
    end

    create index(:pairing_history, [:privy_user_id], prefix: "regent_agents")

    execute("""
    INSERT INTO regent_agents.pairing_history
      (id, privy_user_id, wallet, name, harness, paired_at, last_contact_at,
       human_id, same_person_agent_count)
    SELECT id, privy_user_id, wallet, name, harness, paired_at, last_contact_at,
           human_id, same_person_agent_count
    FROM regent_agents.paired_agents
    """)

    execute("""
    CREATE FUNCTION regent_agents.retain_pairing_episode() RETURNS trigger
    LANGUAGE plpgsql AS $$
    BEGIN
      IF TG_OP = 'DELETE' THEN
        UPDATE regent_agents.pairing_history SET revoked_at = clock_timestamp()
        WHERE id = OLD.id AND revoked_at IS NULL;
        RETURN OLD;
      END IF;
      INSERT INTO regent_agents.pairing_history
        (id, privy_user_id, wallet, name, harness, paired_at, last_contact_at,
         human_id, same_person_agent_count)
      VALUES (NEW.id, NEW.privy_user_id, NEW.wallet, NEW.name, NEW.harness,
              NEW.paired_at, NEW.last_contact_at, NEW.human_id, NEW.same_person_agent_count)
      ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, harness = EXCLUDED.harness,
        last_contact_at = EXCLUDED.last_contact_at, human_id = EXCLUDED.human_id,
        same_person_agent_count = EXCLUDED.same_person_agent_count;
      RETURN NEW;
    END;
    $$
    """)

    execute("""
    CREATE TRIGGER retain_pairing_episode AFTER INSERT OR UPDATE OR DELETE
    ON regent_agents.paired_agents FOR EACH ROW
    EXECUTE FUNCTION regent_agents.retain_pairing_episode()
    """)
  end

  def down do
    raise "Pairing history is retained; deploy a forward repair instead of deleting episodes"
  end
end
