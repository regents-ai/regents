defmodule AshPlatform.DatabaseConfigTest do
  use ExUnit.Case, async: true

  alias AshPlatform.DatabaseConfig

  @pooled "postgresql://pooled_user:pooled-secret@pool.example.test:5432/ash_platform"
  @direct "postgresql://direct_user:direct-secret@direct.example.test:5432/ash_platform"
  @mpg_pooled "postgresql://pooled_user:pooled-secret@pgbouncer.nvwq9ozp9ye03kl1.flympg.net:5432/ash_platform"
  @mpg_direct "postgresql://direct_user:direct-secret@direct.nvwq9ozp9ye03kl1.flympg.net:5432/ash_platform"
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

  test "production runtime selects only the exact direct MPG host from the legacy pooled variable" do
    config =
      DatabaseConfig.runtime_config!(
        :prod,
        env(%{
          "DATABASE_POOLED_URL" => @mpg_direct,
          "DATABASE_DIRECT_URL" => @direct
        })
      )

    effective = effective_repo_config(config)
    assert effective[:hostname] == "direct.nvwq9ozp9ye03kl1.flympg.net"
    assert effective[:socket_options] == @socket_options
    refute Keyword.has_key?(effective, :prepare)
    assert_verified_tls(effective[:ssl], "direct.nvwq9ozp9ye03kl1.flympg.net")
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

  test "release selects the exact direct MPG host only for the exact rehearsal target" do
    config =
      DatabaseConfig.release_config!(
        env(%{
          "ASH_PLATFORM_DATABASE_TARGET_MODE" => "rehearsal",
          "ASH_PLATFORM_DATABASE_CLUSTER_ID" => "nvwq9ozp9ye03kl1",
          "ASH_PLATFORM_DATABASE_CLUSTER_NAME" => "regents-pg-test",
          "DATABASE_POOLED_URL" => @pooled,
          "DATABASE_DIRECT_URL" => @mpg_direct
        })
      )

    effective = effective_repo_config(config)
    assert effective[:hostname] == "direct.nvwq9ozp9ye03kl1.flympg.net"
    refute Keyword.has_key?(effective, :prepare)
    assert_verified_tls(effective[:ssl], "direct.nvwq9ozp9ye03kl1.flympg.net")
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

  test "development non-MPG remote and local configurations remain unchanged" do
    remote = env(rehearsal_env(%{"DATABASE_POOLED_URL" => @pooled}))
    config = DatabaseConfig.runtime_config!(:dev, remote)
    assert config == [url: @pooled, socket_options: @socket_options]
    refute Keyword.has_key?(config, :ssl)

    local = DatabaseConfig.runtime_config!(:dev, env(%{"USER" => "local-user"}))

    refute Keyword.has_key?(local, :ssl)
    refute Keyword.has_key?(local, :socket_options)
  end

  test "Fly MPG pooled access uses verified TLS and unnamed prepares" do
    config =
      DatabaseConfig.runtime_config!(
        :dev,
        env(rehearsal_env(%{"DATABASE_POOLED_URL" => @mpg_pooled}))
      )

    effective = effective_repo_config(config)

    assert effective[:url] == nil
    assert effective[:hostname] == "pgbouncer.nvwq9ozp9ye03kl1.flympg.net"
    assert effective[:socket_options] == @socket_options
    assert effective[:prepare] == :unnamed
    assert_verified_tls(effective[:ssl], "pgbouncer.nvwq9ozp9ye03kl1.flympg.net")
  end

  test "Fly MPG direct access uses verified TLS without pooled prepare mode" do
    config =
      DatabaseConfig.release_config!(env(rehearsal_env(%{"DATABASE_DIRECT_URL" => @mpg_direct})))

    effective = effective_repo_config(config)

    assert effective[:url] == nil
    assert effective[:hostname] == "direct.nvwq9ozp9ye03kl1.flympg.net"
    assert effective[:socket_options] == @socket_options
    refute Keyword.has_key?(effective, :prepare)
    assert_verified_tls(effective[:ssl], "direct.nvwq9ozp9ye03kl1.flympg.net")
  end

  test "Fly MPG rejects every nonempty URL query before Ecto can override secure options" do
    for query <- [
          "ssl=false",
          "SSL=false",
          "s%73l=false",
          "ssl_opts=verify_none",
          "prepare=named",
          "pre%70are=named",
          "hostname=attacker.example",
          "pool_size=5"
        ] do
      url = "#{@mpg_pooled}?#{query}"

      error =
        assert_raise RuntimeError, fn ->
          DatabaseConfig.runtime_config!(
            :dev,
            env(rehearsal_env(%{"DATABASE_POOLED_URL" => url}))
          )
        end

      assert Exception.message(error) ==
               "DATABASE_POOLED_URL must be a valid PostgreSQL URL for the approved target"

      refute Exception.message(error) =~ "pooled-secret"
      refute Exception.message(error) =~ url
    end
  end

  test "every Fly MPG subdomain gets TLS but lookalike and root hosts keep existing output" do
    mpg_url = "postgresql://user:secret@custom.cluster.flympg.net:5432/ash_platform"

    mpg =
      DatabaseConfig.runtime_config!(
        :dev,
        env(rehearsal_env(%{"DATABASE_POOLED_URL" => mpg_url}))
      )

    assert_verified_tls(mpg[:ssl], "custom.cluster.flympg.net")
    refute Keyword.has_key?(mpg, :prepare)

    for url <- [
          "postgresql://user:secret@evilflympg.net:5432/ash_platform",
          "postgresql://user:secret@flympg.net:5432/ash_platform"
        ] do
      assert DatabaseConfig.runtime_config!(
               :dev,
               env(rehearsal_env(%{"DATABASE_POOLED_URL" => url}))
             ) == [url: url, socket_options: @socket_options]
    end
  end

  test "production and release reject every host except the exact direct cluster hostname" do
    invalid_hosts = [
      "pgbouncer.nvwq9ozp9ye03kl1.flympg.net",
      "direct.another-cluster.flympg.net",
      "flympg.net",
      "direct.nvwq9ozp9ye03kl1.flympg.net.attacker.example",
      "direct.nvwq9ozp9ye03kl1.evilflympg.net"
    ]

    for host <- invalid_hosts,
        {selector, variable} <- [
          {fn url ->
             DatabaseConfig.runtime_config!(:prod, env(%{"DATABASE_POOLED_URL" => url}))
           end, "DATABASE_POOLED_URL"},
          {fn url ->
             DatabaseConfig.release_config!(env(rehearsal_env(%{"DATABASE_DIRECT_URL" => url})))
           end, "DATABASE_DIRECT_URL"}
        ] do
      url = "postgresql://sentinel-user:sentinel-secret@#{host}:5432/ash_platform"

      error =
        assert_raise RuntimeError, fn -> selector.(url) end

      assert Exception.message(error) ==
               "#{variable} must be a valid PostgreSQL URL for the approved target"

      refute Exception.message(error) =~ "sentinel"
      refute Exception.message(error) =~ url
    end
  end

  test "the admitted production host is case-normalized before Repo parsing" do
    uppercase =
      "postgresql://user:secret@DIRECT.NVWQ9OZP9YE03KL1.FLYMPG.NET:5432/ash_platform"

    effective =
      :prod
      |> DatabaseConfig.runtime_config!(env(%{"DATABASE_POOLED_URL" => uppercase}))
      |> effective_repo_config()

    assert effective[:hostname] == "direct.nvwq9ozp9ye03kl1.flympg.net"
    assert_verified_tls(effective[:ssl], "direct.nvwq9ozp9ye03kl1.flympg.net")
    refute Keyword.has_key?(effective, :prepare)
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

  defp effective_repo_config(config) do
    {url, explicit} = Keyword.pop(config, :url)
    Keyword.merge(explicit, Ecto.Repo.Supervisor.parse_url(url))
  end
end
