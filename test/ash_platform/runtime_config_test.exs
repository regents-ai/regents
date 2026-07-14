defmodule AshPlatform.RuntimeConfigTest do
  use ExUnit.Case, async: false

  @runtime_config Path.expand("../../config/runtime.exs", __DIR__)

  setup do
    names = [
      "PRIVY_APP_ID",
      "PRIVY_VERIFICATION_KEY",
      "REGENT_ADMIN_WALLET_ADDRESSES",
      "DATABASE_POOLED_URL",
      "DATABASE_DIRECT_URL",
      "DATABASE_URL",
      "ASH_PLATFORM_DATABASE_CLUSTER_ID",
      "ASH_PLATFORM_DATABASE_CLUSTER_NAME",
      "ASH_PLATFORM_DATABASE_TARGET_MODE",
      "ASH_PLATFORM_RELEASE_COMMAND",
      "FLY_APP_NAME"
    ]

    previous = Map.new(names, &{&1, System.get_env(&1)})
    Enum.each(names, &System.delete_env/1)

    on_exit(fn ->
      Enum.each(previous, fn {name, value} -> restore_env(name, value) end)
    end)

    :ok
  end

  test "Privy verification key accepts secret-manager-safe escaped PEM newlines" do
    System.put_env("PRIVY_APP_ID", "local-privy-app")

    System.put_env(
      "PRIVY_VERIFICATION_KEY",
      "-----BEGIN PUBLIC KEY-----\\r\\nabc123\\n-----END PUBLIC KEY-----"
    )

    assert privy_config() == [
             app_id: "local-privy-app",
             verification_key: "-----BEGIN PUBLIC KEY-----\nabc123\n-----END PUBLIC KEY-----"
           ]
  end

  test "Privy verification key preserves a native multiline PEM" do
    pem = "-----BEGIN PUBLIC KEY-----\nabc123\n-----END PUBLIC KEY-----"
    System.put_env("PRIVY_APP_ID", "local-privy-app")
    System.put_env("PRIVY_VERIFICATION_KEY", pem)

    assert privy_config() == [app_id: "local-privy-app", verification_key: pem]
  end

  test "comment moderation accepts a comma-separated admin wallet allowlist" do
    System.put_env(
      "REGENT_ADMIN_WALLET_ADDRESSES",
      " 0x1111111111111111111111111111111111111111,0x2222222222222222222222222222222222222222 "
    )

    assert runtime_config(:admin_wallet_addresses) == [
             "0x1111111111111111111111111111111111111111",
             "0x2222222222222222222222222222222222222222"
           ]
  end

  test "test runtime keeps its fixed local repository despite database environment values" do
    System.put_env("DATABASE_POOLED_URL", "postgresql://pooled:secret@remote.test/db")
    System.put_env("DATABASE_DIRECT_URL", "postgresql://direct:secret@remote.test/db")
    System.put_env("DATABASE_URL", "postgresql://legacy:secret@remote.test/db")

    assert runtime_repo_config(:test) == nil

    test_repo =
      "config/test.exs"
      |> Config.Reader.read!(env: :test, target: :host)
      |> get_in([:ash_platform, AshPlatform.Repo])

    assert Keyword.take(test_repo, [:hostname, :port, :database]) == [
             hostname: "127.0.0.1",
             port: 5432,
             database: "ash_platform_test"
           ]
  end

  test "production runtime enables the repository with pooled access" do
    pooled = "postgresql://pooled:secret@pool.example.test/ash_platform"
    System.put_env("DATABASE_POOLED_URL", pooled)
    System.put_env("DATABASE_DIRECT_URL", "postgresql://direct:secret@direct.example.test/db")

    config = read_runtime_config(:prod)

    assert get_in(config, [:ash_platform, :database_startup_enabled])
    assert get_in(config, [:ash_platform, AshPlatform.Repo]) == [url: pooled]
  end

  test "production runtime fails closed without pooled access" do
    assert_raise RuntimeError, "DATABASE_POOLED_URL is required", fn ->
      read_runtime_config(:prod)
    end
  end

  test "migration runtime selects direct access only for the exact rehearsal target" do
    direct = "postgresql://direct:secret@direct.example.test/ash_platform"
    System.put_env("ASH_PLATFORM_RELEASE_COMMAND", "migrate")
    System.put_env("ASH_PLATFORM_DATABASE_TARGET_MODE", "rehearsal")
    System.put_env("ASH_PLATFORM_DATABASE_CLUSTER_ID", "nvwq9ozp9ye03kl1")
    System.put_env("ASH_PLATFORM_DATABASE_CLUSTER_NAME", "regents-pg-test")
    System.put_env("DATABASE_DIRECT_URL", direct)

    assert runtime_repo_config(:prod) == [url: direct]
  end

  test "migration runtime rejects an arbitrary direct URL without rehearsal identity" do
    System.put_env("ASH_PLATFORM_RELEASE_COMMAND", "migrate")
    System.put_env("DATABASE_DIRECT_URL", "postgresql://direct:secret@direct.example.test/db")

    assert_raise RuntimeError,
                 "database migration requires rehearsal mode for cluster nvwq9ozp9ye03kl1 named regents-pg-test",
                 fn -> runtime_repo_config(:prod) end
  end

  test "migration runtime refuses production mode before reading direct access" do
    System.put_env("ASH_PLATFORM_RELEASE_COMMAND", "migrate")
    System.put_env("ASH_PLATFORM_DATABASE_TARGET_MODE", "production")

    assert_raise RuntimeError,
                 "production migration requires separate Chief-authorized production migration configuration",
                 fn -> runtime_repo_config(:prod) end
  end

  defp privy_config do
    runtime_config(:privy)
  end

  defp runtime_config(key) when is_atom(key) do
    read_runtime_config(:dev)
    |> get_in([:ash_platform, key])
  end

  defp read_runtime_config(environment) do
    @runtime_config
    |> Config.Reader.read!(env: environment, target: :host)
  end

  defp runtime_repo_config(environment),
    do: get_in(read_runtime_config(environment), [:ash_platform, AshPlatform.Repo])

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)
end
