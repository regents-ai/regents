defmodule AshPlatform.NamesFixtures do
  @moduledoc """
  The imported historical-names table for tests. The Ash resource deliberately
  has no mutation actions and never migrates this table, so tests that read it
  create it here and insert their own synthetic rows.
  """

  alias AshPlatform.Repo

  @doc "Creates the retained claim table once in the prepared disposable database."
  def ensure_claims_table! do
    expected = "ash_platform" <> System.fetch_env!("MIX_TEST_PARTITION") <> "_test"

    unless Repo.config()[:database] == expected,
      do: raise("Claims fixtures require the prepared disposable database")

    Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
      # Complete captured column contract; fixture data is synthetic, never copied customer rows.
      Ecto.Adapters.SQL.query!(Repo, "CREATE SCHEMA IF NOT EXISTS regent_names")

      Ecto.Adapters.SQL.query!(Repo, """
      CREATE TABLE IF NOT EXISTS regent_names.basenames_mints (
        id bigint PRIMARY KEY, parent_node varchar(66) NOT NULL, parent_name text NOT NULL,
        label varchar(63) NOT NULL, fqdn text NOT NULL, node varchar(66) NOT NULL UNIQUE,
        ens_fqdn text, ens_node varchar(66), owner_address varchar(42) NOT NULL,
        tx_hash varchar(66) NOT NULL, ens_tx_hash varchar(66), ens_assigned_at timestamptz,
        payment_tx_hash varchar(66), payment_chain_id integer, price_wei bigint,
        is_free boolean NOT NULL DEFAULT false, is_in_use boolean NOT NULL DEFAULT false,
        created_at timestamptz NOT NULL DEFAULT now(), claim_status varchar(255) NOT NULL DEFAULT 'reserved',
        upgrade_tx_hash varchar(255), upgraded_at timestamp,
        formation_agent_slug varchar(255), attached_agent_slug varchar(255)
      )
      """)
    end)

    :ok
  end

  @doc "Inserts one synthetic claim row inside the caller's sandbox."
  def insert_claim(id, owner, extra \\ %{}) do
    row =
      Map.merge(
        %{
          id: id,
          parent_node: "parent",
          parent_name: "agent.base.eth",
          label: "name-#{id}",
          fqdn: "name-#{id}.agent.base.eth",
          ens_fqdn: "name-#{id}.regent.eth",
          node: "node-#{id}",
          owner_address: owner,
          tx_hash: "tx-#{id}"
        },
        extra
      )

    # Fixture-only SQL: the historical Ash resource deliberately has no mutation actions.
    Repo.insert_all("basenames_mints", [row], prefix: "regent_names")
  end
end
