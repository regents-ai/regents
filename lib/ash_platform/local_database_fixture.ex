defmodule AshPlatform.LocalDatabaseFixture do
  @moduledoc false

  def ensure_human_accounts! do
    repo = AshPlatform.Repo.config()
    validate_target!(current_env(), repo)

    Ecto.Adapters.SQL.query!(AshPlatform.Repo, "CREATE SCHEMA IF NOT EXISTS platform", [])

    Ecto.Adapters.SQL.query!(
      AshPlatform.Repo,
      """
      CREATE TABLE IF NOT EXISTS platform.platform_human_users (
      id bigserial PRIMARY KEY,
        privy_user_id varchar(255) NOT NULL UNIQUE,
        wallet_address varchar(255),
        wallet_addresses varchar(255)[] NOT NULL DEFAULT '{}',
      world_human_id varchar(255) UNIQUE,
        world_verified_at timestamp(0) without time zone,
        display_name varchar(80),
        avatar jsonb,
        created_at timestamp(0) without time zone NOT NULL,
        updated_at timestamp(0) without time zone NOT NULL
      )
      """,
      []
    )

    migrate_application_schema!()
    seed_techtree!()
  end

  def validate_target!(env, repo) when is_list(repo) do
    host = to_string(repo[:hostname])
    database = to_string(repo[:database])

    if env in [:dev, :test] and host in ["127.0.0.1", "localhost", "::1"] and
         (String.ends_with?(database, "_dev") or String.ends_with?(database, "_test")) do
      :ok
    else
      raise "local human-account fixture refused unsafe database target"
    end
  end

  defp current_env do
    if Code.ensure_loaded?(Mix), do: Mix.env(), else: :prod
  end

  defp migrate_application_schema! do
    migrations_path = Path.expand("../../priv/repo/migrations", __DIR__)
    Ecto.Migrator.run(AshPlatform.Repo, migrations_path, :up, all: true)
  end

  defp seed_techtree! do
    case AshPlatform.Techtree.ensure_seed_trees(actor: %AshPlatform.Actors.System{}) do
      :ok -> :ok
      {:error, error} -> raise error
    end
  end
end
