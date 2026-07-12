defmodule AshPlatformWeb.BoundaryTest do
  use ExUnit.Case, async: true

  @forbidden_runtime_boundaries [
    "DATABASE_URL",
    "check_origin: false",
    "../platform",
    "/platform/"
  ]

  @excluded_product_surfaces ~w(
    authentication privy provider billing payment wallet staking redemption
    autolaunch xmtp siwa 0.25 .25
  )

  test "the Techtree foundation has no old-platform or environment database boundary" do
    paths =
      ["mix.exs" | Path.wildcard("{config,lib,test}/**/*.{ex,exs,heex}")]
      |> List.delete(__ENV__.file |> Path.relative_to_cwd())

    for path <- paths,
        forbidden <- @forbidden_runtime_boundaries do
      refute File.read!(path) =~ forbidden, "#{path} contains forbidden boundary #{forbidden}"
    end

    assert File.exists?("lib/ash_platform/repo.ex")
    assert Path.wildcard("priv/repo/migrations/*") != []
  end

  test "the application starts only the admitted Repo and Ash domain" do
    assert Application.fetch_env!(:ash_platform, :ash_domains) == [AshPlatform.Techtree]
    assert Application.fetch_env!(:ash_platform, :ecto_repos) == [AshPlatform.Repo]

    children = Supervisor.which_children(AshPlatform.Supervisor)
    assert Enum.any?(children, fn {id, _pid, _type, _modules} -> id == AshPlatform.Repo end)
  end

  test "the admitted database slice contains no excluded product surface" do
    paths =
      Path.wildcard("lib/ash_platform/techtree/**/*.ex") ++
        [
          "lib/ash_platform/techtree.ex",
          "lib/ash_platform/repo.ex",
          "contracts/api-contract.openapiv3.yaml"
        ]

    for path <- paths,
        excluded <- @excluded_product_surfaces do
      refute path |> File.read!() |> String.downcase() =~ excluded,
             "#{path} contains excluded product surface #{excluded}"
    end

    contract = YamlElixir.read_from_file!("contracts/api-contract.openapiv3.yaml")
    assert Map.keys(contract["paths"]) == ["/api/techtree/v1/tree/nodes"]
  end

  test "the protected human-user table scaffold remains test infrastructure only" do
    fixture = File.read!("lib/ash_platform/local_database_fixture.ex")

    assert fixture =~ "CREATE TABLE IF NOT EXISTS platform.platform_human_users"
    assert fixture =~ "env in [:dev, :test]"
    assert fixture =~ "host in [\"127.0.0.1\", \"localhost\", \"::1\"]"
    assert fixture =~ "String.ends_with?(database, \"_dev\")"
    assert fixture =~ "String.ends_with?(database, \"_test\")"

    assert Path.wildcard("lib/ash_platform/{accounts,auth,authentication}/**/*.{ex,exs}") == []

    router = File.read!("lib/ash_platform_web/router.ex") |> String.downcase()
    contract = File.read!("contracts/api-contract.openapiv3.yaml") |> String.downcase()

    for product_surface <- ["accounts", "auth", "privy", "wallet"] do
      refute router =~ product_surface
      refute contract =~ product_surface
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

  test "notebook proofs use exact environment origin allowlists" do
    {_ast, default_origins} =
      "config/config.exs"
      |> File.read!()
      |> Code.string_to_quoted!()
      |> Macro.prewalk([], fn
        {:config, _, [:ash_platform, :notebook_origins, origins]} = node, declarations ->
          {node, [origins | declarations]}

        node, declarations ->
          {node, declarations}
      end)

    dev_config = Config.Reader.read!("config/dev.exs", env: :dev)

    assert default_origins == [["https://notebooks.regents.sh"]]

    assert dev_config |> Keyword.fetch!(:ash_platform) |> Keyword.fetch!(:notebook_origins) ==
             ["http://127.0.0.1:4001"]

    assert Application.fetch_env!(:ash_platform, :notebook_origins) == [
             "http://127.0.0.1:4003"
           ]
  end
end
