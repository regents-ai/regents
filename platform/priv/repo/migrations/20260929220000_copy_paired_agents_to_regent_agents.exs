defmodule Regents.Repo.Migrations.CopyPairedAgentsToRegentAgents do
  @moduledoc """
  Paired agents move to the pairing every Regent site shares, which names the
  person by their Privy user ID. Each agent keeps its id, so a page showing one
  still finds it. Pairing codes live ten minutes and are not carried over.
  The old table stays until its rows are checked against the copy.
  """

  use Ecto.Migration

  def up do
    execute("""
    INSERT INTO regent_agents.paired_agents
      (id, privy_user_id, wallet, name, harness, paired_at, last_contact_at)
    SELECT pa.id, h.privy_user_id, pa.wallet, pa.name, pa.harness, pa.paired_at, pa.last_contact_at
    FROM regents_app.paired_agents pa
    JOIN regent_names.platform_human_users h ON h.id = pa.human_account_id
    """)
  end

  def down, do: raise(Ecto.MigrationError, "the copied pairings cannot be taken back")
end
