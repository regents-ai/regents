defmodule AshPlatform.Release do
  @moduledoc false

  @app :ash_platform

  def migration_config!(getenv \\ &System.get_env/1) do
    AshPlatform.DatabaseConfig.release_config!(getenv)
  end

  def migrate do
    load_app()
    Application.put_env(@app, AshPlatform.Repo, migration_config!())

    Ecto.Migrator.with_repo(AshPlatform.Repo, fn repo ->
      Ecto.Migrator.run(repo, migrations_path(), :up, all: true)
    end)
  end

  defp load_app do
    case Application.load(@app) do
      :ok -> :ok
      {:error, {:already_loaded, @app}} -> :ok
    end
  end

  defp migrations_path do
    Application.app_dir(@app, "priv/repo/migrations")
  end
end
