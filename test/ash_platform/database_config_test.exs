defmodule AshPlatform.DatabaseConfigTest do
  use ExUnit.Case, async: true

  alias AshPlatform.DatabaseConfig

  @pooled "postgresql://pooled_user:pooled-secret@pool.example.test:5432/ash_platform"
  @direct "postgresql://direct_user:direct-secret@direct.example.test:5432/ash_platform"
  @mpg_pooled "postgresql://pooled_user:pooled-secret@pgbouncer.cluster.flympg.net:5432/ash_platform"
  @mpg_direct "postgresql://direct_user:direct-secret@direct.cluster.flympg.net:5432/ash_platform"
  @socket_options [:inet6]

  test "test always keeps the fixed local database" do
    config =
      DatabaseConfig.runtime_config!(
        :test,
        env(%{
          "DATABASE_POOLED_URL" => @pooled,
          "DATABASE_DIRECT_URL" => @direct,
          "ASH_PLATFORM_DATABASE_CLUSTER_ID" => "wrong",
          "ASH_PLATFORM_DATABASE_CLUSTER_NAME" => "regents-platform-prod"
        })
      )

    assert config == nil
  end

  test "production runtime selects only the pooled URL" do
    assert DatabaseConfig.runtime_config!(
             :prod,
             env(%{
               "DATABASE_POOLED_URL" => @pooled,
               "DATABASE_DIRECT_URL" => @direct
             })
           ) == [url: @pooled, socket_options: @socket_options]
  end

  test "production runtime fails closed when pooled URL is missing" do
    assert_raise RuntimeError, "DATABASE_POOLED_URL is required", fn ->
      DatabaseConfig.runtime_config!(:prod, env(%{"DATABASE_DIRECT_URL" => @direct}))
    end
  end

  test "the generic database URL cannot satisfy production runtime" do
    assert_raise RuntimeError, "DATABASE_POOLED_URL is required", fn ->
      DatabaseConfig.runtime_config!(:prod, env(%{"DATABASE_URL" => @pooled}))
    end
  end

  test "release selects direct access only for the exact rehearsal target" do
    assert DatabaseConfig.release_config!(
             env(%{
               "ASH_PLATFORM_DATABASE_TARGET_MODE" => "rehearsal",
               "ASH_PLATFORM_DATABASE_CLUSTER_ID" => "nvwq9ozp9ye03kl1",
               "ASH_PLATFORM_DATABASE_CLUSTER_NAME" => "regents-pg-test",
               "DATABASE_POOLED_URL" => @pooled,
               "DATABASE_DIRECT_URL" => @direct
             })
           ) == [url: @direct, socket_options: @socket_options]
  end

  test "release fails closed when direct URL is missing" do
    assert_raise RuntimeError, "DATABASE_DIRECT_URL is required", fn ->
      DatabaseConfig.release_config!(env(rehearsal_env(%{"DATABASE_POOLED_URL" => @pooled})))
    end
  end

  test "release rejects missing, incomplete, wrong, and deployed rehearsal targets" do
    invalid_targets = [
      %{"DATABASE_DIRECT_URL" => @direct},
      %{
        "ASH_PLATFORM_DATABASE_TARGET_MODE" => "rehearsal",
        "ASH_PLATFORM_DATABASE_CLUSTER_ID" => "nvwq9ozp9ye03kl1",
        "DATABASE_DIRECT_URL" => @direct
      },
      rehearsal_env(%{
        "ASH_PLATFORM_DATABASE_CLUSTER_ID" => "wrong",
        "DATABASE_DIRECT_URL" => @direct
      }),
      rehearsal_env(%{"FLY_APP_NAME" => "platform-phx", "DATABASE_DIRECT_URL" => @direct}),
      rehearsal_env(%{
        "FLY_APP_NAME" => "regents-platform-prod",
        "DATABASE_DIRECT_URL" => @direct
      })
    ]

    for values <- invalid_targets do
      assert_raise RuntimeError,
                   "database migration requires rehearsal mode for cluster nvwq9ozp9ye03kl1 named regents-pg-test",
                   fn -> DatabaseConfig.release_config!(env(values)) end
    end
  end

  test "production migration mode requires separate Chief authorization" do
    assert_raise RuntimeError,
                 "production migration requires separate Chief-authorized production migration configuration",
                 fn ->
                   DatabaseConfig.release_config!(
                     env(%{
                       "ASH_PLATFORM_DATABASE_TARGET_MODE" => "production",
                       "DATABASE_DIRECT_URL" => @direct
                     })
                   )
                 end
  end

  test "release rejects production identity embedded or encoded in direct URLs" do
    for url <- [
          "postgresql://user:secret@platform-phx.example.test/db",
          "postgresql://user:secret@safe.example.test/regents-platform-prod",
          "postgresql://regents%2Dplatform%2Dprod:secret@safe.example.test/db"
        ] do
      error =
        assert_raise RuntimeError, fn ->
          DatabaseConfig.release_config!(env(rehearsal_env(%{"DATABASE_DIRECT_URL" => url})))
        end

      assert Exception.message(error) ==
               "DATABASE_DIRECT_URL must be a valid PostgreSQL URL for the approved target"

      refute Exception.message(error) =~ url
      refute Exception.message(error) =~ "secret"
    end
  end

  test "development local database keeps a migration-safe connection pool" do
    assert DatabaseConfig.runtime_config!(:dev, env(%{"USER" => "local-user"})) == [
             username: "local-user",
             password: nil,
             hostname: "127.0.0.1",
             port: 5432,
             database: "ash_platform_dev",
             pool_size: 2
           ]
  end

  test "development accepts the exact rehearsal target and selects pooled access" do
    assert DatabaseConfig.runtime_config!(
             :dev,
             env(%{
               "ASH_PLATFORM_DATABASE_CLUSTER_ID" => "nvwq9ozp9ye03kl1",
               "ASH_PLATFORM_DATABASE_CLUSTER_NAME" => "regents-pg-test",
               "DATABASE_POOLED_URL" => @pooled,
               "DATABASE_DIRECT_URL" => @direct
             })
           ) == [url: @pooled, socket_options: @socket_options]
  end

  test "development rejects incomplete, wrong, production, and deployed-app targets" do
    invalid_targets = [
      %{"ASH_PLATFORM_DATABASE_CLUSTER_ID" => "nvwq9ozp9ye03kl1"},
      %{
        "ASH_PLATFORM_DATABASE_CLUSTER_ID" => "wrong",
        "ASH_PLATFORM_DATABASE_CLUSTER_NAME" => "regents-pg-test"
      },
      %{
        "ASH_PLATFORM_DATABASE_CLUSTER_ID" => "nvwq9ozp9ye03kl1",
        "ASH_PLATFORM_DATABASE_CLUSTER_NAME" => "regents-platform-prod"
      },
      %{"FLY_APP_NAME" => "platform-phx"}
    ]

    for values <- invalid_targets do
      assert_raise RuntimeError,
                   "remote database access requires cluster nvwq9ozp9ye03kl1 named regents-pg-test",
                   fn -> DatabaseConfig.runtime_config!(:dev, env(values)) end
    end
  end

  test "canonical URLs reject production identity in hostname, database, or username" do
    malicious_urls = [
      "postgresql://user:secret@regents-platform-prod.example.test/db",
      "postgresql://user:secret@safe.example.test/regents-platform-prod",
      "postgresql://platform-phx:secret@safe.example.test/db"
    ]

    for url <- malicious_urls do
      assert_raise RuntimeError,
                   "DATABASE_POOLED_URL must be a valid PostgreSQL URL for the approved target",
                   fn ->
                     DatabaseConfig.runtime_config!(:prod, env(%{"DATABASE_POOLED_URL" => url}))
                   end
    end
  end

  test "URL errors never reveal credentials" do
    sentinel = "sentinel-user:sentinel-password"
    invalid_url = "http://#{sentinel}@example.test/database"

    error =
      assert_raise RuntimeError, fn ->
        DatabaseConfig.runtime_config!(:prod, env(%{"DATABASE_POOLED_URL" => invalid_url}))
      end

    refute Exception.message(error) =~ "sentinel"
    refute Exception.message(error) =~ invalid_url
  end

  test "malformed pooled and direct URLs fail closed with canonical variable names" do
    for {selector, variable} <- [
          {&DatabaseConfig.runtime_config!(:prod, &1), "DATABASE_POOLED_URL"},
          {fn getenv -> DatabaseConfig.release_config!(env(rehearsal_env_from(getenv))) end,
           "DATABASE_DIRECT_URL"}
        ] do
      error =
        assert_raise RuntimeError, fn ->
          selector.(
            env(%{variable => "postgresql://sentinel:secret@example.test/db?pool_size=invalid"})
          )
        end

      assert Exception.message(error) =~ variable
      refute Exception.message(error) =~ "sentinel"
      refute Exception.message(error) =~ "secret"
    end
  end

  test "non-MPG remote connections keep IPv6-only output while the local database is unchanged" do
    remote =
      env(rehearsal_env(%{"DATABASE_POOLED_URL" => @pooled, "DATABASE_DIRECT_URL" => @direct}))

    for config <- [
          DatabaseConfig.runtime_config!(:prod, remote),
          DatabaseConfig.runtime_config!(:dev, remote),
          DatabaseConfig.release_config!(remote)
        ] do
      assert config[:socket_options] == @socket_options
      refute Keyword.has_key?(config, :ssl)
    end

    local = DatabaseConfig.runtime_config!(:dev, env(%{"USER" => "local-user"}))

    refute Keyword.has_key?(local, :ssl)
    refute Keyword.has_key?(local, :socket_options)
  end

  test "Fly MPG pooled access uses verified TLS and unnamed prepares" do
    config =
      DatabaseConfig.runtime_config!(
        :prod,
        env(%{"DATABASE_POOLED_URL" => @mpg_pooled})
      )

    assert config[:url] == @mpg_pooled
    assert config[:socket_options] == @socket_options
    assert config[:prepare] == :unnamed
    assert_verified_tls(config[:ssl], "pgbouncer.cluster.flympg.net")
  end

  test "Fly MPG direct access uses verified TLS without pooled prepare mode" do
    config =
      DatabaseConfig.release_config!(env(rehearsal_env(%{"DATABASE_DIRECT_URL" => @mpg_direct})))

    assert config[:url] == @mpg_direct
    assert config[:socket_options] == @socket_options
    refute Keyword.has_key?(config, :prepare)
    assert_verified_tls(config[:ssl], "direct.cluster.flympg.net")
  end

  test "every Fly MPG subdomain gets TLS but lookalike and root hosts keep existing output" do
    mpg_url = "postgresql://user:secret@custom.cluster.flympg.net:5432/ash_platform"

    mpg = DatabaseConfig.runtime_config!(:prod, env(%{"DATABASE_POOLED_URL" => mpg_url}))
    assert_verified_tls(mpg[:ssl], "custom.cluster.flympg.net")
    refute Keyword.has_key?(mpg, :prepare)

    for url <- [
          "postgresql://user:secret@evilflympg.net:5432/ash_platform",
          "postgresql://user:secret@flympg.net:5432/ash_platform"
        ] do
      assert DatabaseConfig.runtime_config!(:prod, env(%{"DATABASE_POOLED_URL" => url})) == [
               url: url,
               socket_options: @socket_options
             ]
    end
  end

  defp env(values), do: &Map.get(values, &1)

  defp rehearsal_env(overrides) do
    Map.merge(
      %{
        "ASH_PLATFORM_DATABASE_TARGET_MODE" => "rehearsal",
        "ASH_PLATFORM_DATABASE_CLUSTER_ID" => "nvwq9ozp9ye03kl1",
        "ASH_PLATFORM_DATABASE_CLUSTER_NAME" => "regents-pg-test"
      },
      overrides
    )
  end

  defp rehearsal_env_from(getenv) do
    rehearsal_env(%{"DATABASE_DIRECT_URL" => getenv.("DATABASE_DIRECT_URL")})
  end

  defp assert_verified_tls(ssl, hostname) do
    assert ssl[:verify] == :verify_peer
    assert is_list(ssl[:cacerts]) and ssl[:cacerts] != []
    assert ssl[:server_name_indication] == String.to_charlist(hostname)

    assert is_function(
             get_in(ssl, [:customize_hostname_check, :match_fun]),
             2
           )
  end
end
