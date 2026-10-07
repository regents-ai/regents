defmodule RegentsWeb.BoundaryTest do
  use ExUnit.Case, async: true

  @forbidden ["check_origin: false", "../platform", "/platform/"]

  test "auth has no production database shortcut or old-platform dependency" do
    paths =
      ["mix.exs" | Path.wildcard("{config,lib,test}/**/*.{ex,exs,heex}")]
      |> List.delete(__ENV__.file |> Path.relative_to_cwd())

    for path <- paths,
        forbidden <- @forbidden do
      refute File.read!(path) =~ forbidden, "#{path} contains forbidden boundary #{forbidden}"
    end
  end

  test "the application migrations are the extensions install, the regents_app baseline, agent pairing, its copy to the shared pairing, the removal of the old pairing, the removal of the allowance, Oban and the sign-in time" do
    assert [extensions_migration] =
             Path.wildcard("priv/repo/migrations/*_initial_regents_app_extensions_1.exs")

    assert [baseline_migration] = Path.wildcard("priv/repo/migrations/*_initial_regents_app.exs")
    assert [agent_pairing_migration] = Path.wildcard("priv/repo/migrations/*_agent_pairing.exs")

    assert [activity_drop_migration] =
             Path.wildcard("priv/repo/migrations/*_drop_agent_activities.exs")

    assert [copy_migration] =
             Path.wildcard("priv/repo/migrations/*_copy_paired_agents_to_regent_agents.exs")

    assert [old_pairing_drop_migration] =
             Path.wildcard("priv/repo/migrations/*_drop_old_pairing_tables.exs")

    assert [allowance_drop_migration] =
             Path.wildcard("priv/repo/migrations/*_drop_regent_allowance.exs")

    assert [oban_migration] = Path.wildcard("priv/repo/migrations/*_add_oban.exs")

    assert [signed_in_migration] =
             Path.wildcard("priv/repo/migrations/*_session_signed_in_at.exs")

    assert Enum.sort(Path.wildcard("priv/repo/migrations/*")) ==
             Enum.sort([
               extensions_migration,
               baseline_migration,
               agent_pairing_migration,
               activity_drop_migration,
               copy_migration,
               old_pairing_drop_migration,
               allowance_drop_migration,
               oban_migration,
               signed_in_migration
             ])

    # The sign-in time only adds a column and fills it for bound sessions.
    refute File.read!(signed_in_migration) =~ ~r/\b(DELETE|DROP|TRUNCATE)\b/i

    # The copy only adds rows to the shared pairing.
    copy = File.read!(copy_migration)
    assert copy =~ "INSERT INTO regent_agents.paired_agents"
    refute copy =~ ~r/\b(DELETE|DROP|TRUNCATE|UPDATE)\b/i

    # Each removal names exactly the tables Sean agreed to remove.
    assert drops(activity_drop_migration) == ["drop table(:agent_activities)"]

    assert drops(old_pairing_drop_migration) == [
             "drop table(:paired_agents)",
             "drop table(:agent_pairing_codes)"
           ]

    assert ~r/execute\("([^"]+)"\)/
           |> Regex.scan(File.read!(allowance_drop_migration), capture: :all_but_first)
           |> List.flatten() == [
             "DROP TABLE IF EXISTS regent_allowance.openai_calls",
             "DROP TABLE IF EXISTS regent_allowance.schema_migrations",
             "DROP SCHEMA IF EXISTS regent_allowance"
           ]

    assert_extension_migration(extensions_migration)

    assert_additive_migration(
      baseline_migration,
      [
        "create table(:account_ens_identities",
        "create table(:agent_links",
        "create table(:agent_pairing_codes",
        "create table(:cloud_runtimes",
        "create table(:linked_identities",
        "create table(:regents",
        "create table(:session_authorities",
        "references(:platform_human_users",
        ~s(prefix: "regent_names"),
        "references(:regents",
        ~s(prefix: "regents_app")
      ],
      []
    )

    # Regents' own tables take their schema from the migrator, so the file names
    # a schema only where it reaches another table: the shared account table and
    # the regents table itself. Nothing may name a retired schema.
    baseline = File.read!(baseline_migration)
    refute baseline =~ ~r/create table\(:\w+, [^\n]*prefix:/
    refute baseline =~ "CREATE SCHEMA"

    for retired <- ~w(platform autolaunch discussions techtree public autolaunch_app) do
      refute baseline =~ ~s(prefix: "#{retired}")
    end
  end

  defp drops(path) do
    for line <- String.split(File.read!(path), "\n"),
        line =~ ~r/^\s+drop/,
        do: String.trim(line)
  end

  defp assert_additive_migration(path, required_fragments, allowed_statements) do
    source = File.read!(path)
    [up, _down] = String.split(source, "  def down do", parts: 2)

    for fragment <- required_fragments, do: assert(up =~ fragment)
    refute up =~ "drop("

    statements =
      ~r/execute\("([^"]+)"\)/
      |> Regex.scan(up, capture: :all_but_first)
      |> List.flatten()
      |> Enum.uniq()

    assert statements == allowed_statements
  end

  defp assert_extension_migration(path) do
    source = File.read!(path)
    [up, _down] = String.split(source, "  def down do", parts: 2)

    for function <- [
          "ash_elixir_or",
          "ash_elixir_and",
          "ash_trim_whitespace",
          "ash_raise_error",
          "ash_required",
          "uuid_generate_v7"
        ],
        do: assert(up =~ "CREATE OR REPLACE FUNCTION #{function}")

    refute up =~ "DROP FUNCTION"
    refute up =~ "create table("
    refute up =~ "alter table("
  end

  test "production database startup is enabled only after canonical configuration succeeds" do
    runtime = File.read!("config/runtime.exs")
    assert runtime =~ "config :regents, :database_startup_enabled, true"
    assert runtime =~ "Regents.DatabaseConfig.runtime_config!(config_env())"
    assert runtime =~ "Regents.DatabaseConfig.release_config!()"
    assert runtime =~ ~s|System.get_env("REGENTS_RELEASE_COMMAND") == "migrate"|
  end

  test "runtime code never reads the generic database URL" do
    legacy_lookup = ~s|System.get_env("DATABASE_URL")|

    for path <- Path.wildcard("{config,lib,rel}/**/*"), File.regular?(path) do
      refute File.read!(path) =~ legacy_lookup, "#{path} reads the generic database URL"
    end
  end

  test "development keeps origin protection on an exact loopback allowlist" do
    endpoint_config =
      "config/dev.exs"
      |> Config.Reader.read!(env: :dev)
      |> Keyword.fetch!(:regents)
      |> Keyword.fetch!(RegentsWeb.Endpoint)

    assert Keyword.fetch!(endpoint_config, :check_origin) == [
             "http://localhost:4000",
             "http://127.0.0.1:4000"
           ]
  end

  test "test keeps origin protection on its exact loopback allowlist" do
    endpoint_config =
      "config/test.exs"
      |> Config.Reader.read!(env: :test)
      |> Keyword.fetch!(:regents)
      |> Keyword.fetch!(RegentsWeb.Endpoint)

    port = endpoint_config |> Keyword.fetch!(:http) |> Keyword.fetch!(:port)
    assert Keyword.fetch!(endpoint_config, :check_origin) == ["http://127.0.0.1:#{port}"]
  end
end
