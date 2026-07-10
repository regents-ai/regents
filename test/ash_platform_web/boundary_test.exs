defmodule AshPlatformWeb.BoundaryTest do
  use ExUnit.Case, async: true

  @forbidden [
    "AshPostgres",
    "Ecto.Repo",
    "Ecto.Adapters",
    "Postgrex",
    "DATABASE_URL",
    "check_origin: false",
    "../platform",
    "/platform/"
  ]

  test "Phase 1 has no database, migration, or old-platform boundary" do
    paths =
      ["mix.exs" | Path.wildcard("{config,lib,test}/**/*.{ex,exs,heex}")]
      |> List.delete(__ENV__.file |> Path.relative_to_cwd())

    for path <- paths,
        forbidden <- @forbidden do
      refute File.read!(path) =~ forbidden, "#{path} contains forbidden boundary #{forbidden}"
    end

    refute File.exists?("lib/ash_platform/repo.ex")
    assert Path.wildcard("priv/repo/migrations/*") == []
  end

  test "the application starts no Repo and configures no Ash data domain" do
    assert Application.fetch_env!(:ash_platform, :ash_domains) == []

    children = Supervisor.which_children(AshPlatform.Supervisor)
    refute Enum.any?(children, fn {id, _pid, _type, _modules} -> inspect(id) =~ "Repo" end)
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
