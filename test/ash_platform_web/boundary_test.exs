defmodule AshPlatformWeb.BoundaryTest do
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

  test "the only application migrations are the admitted additive tables" do
    assert [regent_migration] = Path.wildcard("priv/repo/migrations/*_create_regents.exs")

    assert [techtree_migration] =
             Path.wildcard("priv/repo/migrations/*_create_techtree_trees_and_nodes.exs")

    assert [autolaunch_migration] =
             Path.wildcard("priv/repo/migrations/*_create_autolaunch_auctions_and_tokens.exs")

    assert [comments_migration] =
             Path.wildcard("priv/repo/migrations/*_create_record_comments.exs")

    assert [comment_reactions_migration] =
             Path.wildcard("priv/repo/migrations/*_add_techtree_comment_reactions.exs")

    assert [notebook_artifacts_migration] =
             Path.wildcard("priv/repo/migrations/*_add_techtree_notebook_artifacts.exs")

    assert [launch_drafts_migration] =
             Path.wildcard("priv/repo/migrations/*_add_autolaunch_launch_drafts.exs")

    assert [subjects_migration] =
             Path.wildcard("priv/repo/migrations/*_add_autolaunch_subjects_and_actions.exs")

    assert [subject_identity_migration] =
             Path.wildcard(
               "priv/repo/migrations/*_add_autolaunch_subject_id_and_token_linkage.exs"
             )

    assert [cloud_runtimes_migration] =
             Path.wildcard("priv/repo/migrations/*_add_formation_cloud_runtimes.exs")

    assert [public_profile_migration] =
             Path.wildcard("priv/repo/migrations/*_add_public_regent_profile_projection.exs")

    assert [billing_kernel_migration] =
             Path.wildcard("priv/repo/migrations/*_add_prepaid_authorization_kernel.exs")

    assert [ash_functions_migration] =
             Path.wildcard(
               "priv/repo/migrations/*_install_ash_functions_for_billing_extensions_1.exs"
             )

    assert Enum.sort(Path.wildcard("priv/repo/migrations/*")) ==
             Enum.sort([
               regent_migration,
               techtree_migration,
               autolaunch_migration,
               comments_migration,
               comment_reactions_migration,
               notebook_artifacts_migration,
               launch_drafts_migration,
               subjects_migration,
               subject_identity_migration,
               cloud_runtimes_migration,
               public_profile_migration,
               billing_kernel_migration,
               ash_functions_migration
             ])

    assert_additive_migration(
      regent_migration,
      [
        "create table(:regents",
        "references(:platform_human_users"
      ],
      []
    )

    assert_additive_migration(
      techtree_migration,
      [
        "create table(:trees",
        "create table(:nodes",
        "references(:trees",
        ~s(prefix: "techtree")
      ],
      ["CREATE SCHEMA IF NOT EXISTS techtree"]
    )

    assert_additive_migration(
      autolaunch_migration,
      [
        "create table(:auctions",
        "create table(:tokens",
        "references(:auctions",
        ~s(prefix: "autolaunch")
      ],
      ["CREATE SCHEMA IF NOT EXISTS autolaunch"]
    )

    assert_additive_migration(
      comments_migration,
      [
        "create table(:comments",
        "references(:platform_human_users",
        ~s(prefix: "discussions")
      ],
      ["CREATE SCHEMA IF NOT EXISTS discussions"]
    )

    assert_additive_migration(
      comment_reactions_migration,
      [
        "create table(:comment_reactions",
        "references(:comments",
        "references(:platform_human_users",
        ~s(prefix: "discussions")
      ],
      ["CREATE SCHEMA IF NOT EXISTS discussions"]
    )

    assert_additive_migration(
      notebook_artifacts_migration,
      [
        "create table(:notebook_artifacts",
        "references(:nodes",
        ~s(prefix: "techtree")
      ],
      ["CREATE SCHEMA IF NOT EXISTS techtree"]
    )

    assert_additive_migration(
      launch_drafts_migration,
      [
        "create table(:launch_drafts",
        "references(:platform_human_users",
        "references(:regents",
        ~s(prefix: "autolaunch")
      ],
      ["CREATE SCHEMA IF NOT EXISTS autolaunch"]
    )

    assert_additive_migration(
      subjects_migration,
      [
        "create table(:subjects",
        "create table(:subject_actions",
        "references(:subjects",
        ~s(prefix: "autolaunch")
      ],
      ["CREATE SCHEMA IF NOT EXISTS autolaunch"]
    )

    assert_additive_migration(
      subject_identity_migration,
      [
        "alter table(:tokens",
        "alter table(:subjects",
        "add(:subject_id, :text",
        "create unique_index(:subjects, [:subject_id]"
      ],
      []
    )

    assert_additive_migration(
      cloud_runtimes_migration,
      [
        "create table(:cloud_runtimes",
        "references(:platform_human_users",
        "references(:regents"
      ],
      []
    )

    assert_additive_migration(
      public_profile_migration,
      [
        "alter table(:regents)",
        "add(:avatar_url, :text)"
      ],
      []
    )

    assert_additive_migration(
      billing_kernel_migration,
      [
        "create table(:billing_accounts,",
        "create table(:billing_ledger_entries,",
        "create table(:billing_spend_reservations,",
        "billing_accounts_authority_balanced"
      ],
      []
    )

    assert_extension_migration(ash_functions_migration)
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

  test "only the admitted canonical domains are configured" do
    assert Application.fetch_env!(:ash_platform, :ash_domains) == [
             AshPlatform.Accounts,
             AshPlatform.Billing,
             AshPlatform.Discussions,
             AshPlatform.Formation,
             AshPlatform.Techtree,
             AshPlatform.Autolaunch,
             AshPlatform.Redemption,
             AshPlatform.Staking
           ]
  end

  test "production database startup is enabled only after canonical configuration succeeds" do
    runtime = File.read!("config/runtime.exs")
    assert runtime =~ "config :ash_platform, :database_startup_enabled, true"
    assert runtime =~ "AshPlatform.DatabaseConfig.runtime_config!(config_env())"
    assert runtime =~ "AshPlatform.DatabaseConfig.release_config!()"
    assert runtime =~ ~s|System.get_env("ASH_PLATFORM_RELEASE_COMMAND") == "migrate"|
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
      |> Keyword.fetch!(:ash_platform)
      |> Keyword.fetch!(AshPlatformWeb.Endpoint)

    assert Keyword.fetch!(endpoint_config, :check_origin) == [
             "http://localhost:4000",
             "http://127.0.0.1:4000"
           ]
  end

  test "test keeps origin protection on its exact loopback allowlist" do
    endpoint_config =
      "config/test.exs"
      |> Config.Reader.read!(env: :test)
      |> Keyword.fetch!(:ash_platform)
      |> Keyword.fetch!(AshPlatformWeb.Endpoint)

    assert Keyword.fetch!(endpoint_config, :check_origin) == ["http://127.0.0.1:4002"]
  end
end
