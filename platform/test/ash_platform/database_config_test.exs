defmodule AshPlatform.DatabaseConfigTest do
  use ExUnit.Case, async: true

  alias AshPlatform.DatabaseConfig

  @pooled "postgresql://pooled_user:pooled-secret@pool.example.test:5432/ash_platform"
  @direct "postgresql://direct_user:direct-secret@direct.example.test:5432/ash_platform"
  @mpg_pooled "postgresql://pooled_user:pooled-secret@pgbouncer.dzx6qo6xqzvojpv5.flympg.net:5432/ash_platform"
  @mpg_direct "postgresql://direct_user:direct-secret@direct.dzx6qo6xqzvojpv5.flympg.net:5432/ash_platform"
  @socket_options [:inet6]
  @role "ASH_PLATFORM_DEPLOYMENT_ROLE"
  @staging_flycast "postgresql://staging_user:staging-secret@regents-staging-db.flycast:5432/ash_platform"
  @staging_internal "postgresql://staging_user:staging-secret@regents-staging-db.internal:5432/ash_platform"
  @role_error ~s(ASH_PLATFORM_DEPLOYMENT_ROLE must be set to "production" or "staging")

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
    assert effective[:hostname] == "direct.dzx6qo6xqzvojpv5.flympg.net"
    assert effective[:socket_options] == @socket_options
    refute Keyword.has_key?(effective, :prepare)
    assert_verified_tls(effective[:ssl], "direct.dzx6qo6xqzvojpv5.flympg.net")
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

  test "release selects the exact direct MPG host only for the exact production target" do
    config =
      DatabaseConfig.release_config!(
        env(%{
          "ASH_PLATFORM_DATABASE_TARGET_MODE" => "production",
          "ASH_PLATFORM_DATABASE_CLUSTER_ID" => "dzx6qo6xqzvojpv5",
          "ASH_PLATFORM_DATABASE_CLUSTER_NAME" => "regents-platform-prod",
          "DATABASE_POOLED_URL" => @pooled,
          "DATABASE_DIRECT_URL" => @mpg_direct
        })
      )

    effective = effective_repo_config(config)
    assert effective[:hostname] == "direct.dzx6qo6xqzvojpv5.flympg.net"
    refute Keyword.has_key?(effective, :prepare)
    assert_verified_tls(effective[:ssl], "direct.dzx6qo6xqzvojpv5.flympg.net")
  end

  test "release fails closed when direct URL is missing" do
    assert_raise RuntimeError, "DATABASE_DIRECT_URL is required", fn ->
      DatabaseConfig.release_config!(env(production_env(%{"DATABASE_POOLED_URL" => @pooled})))
    end
  end

  test "release rejects missing, incomplete, wrong, and retired production targets" do
    invalid_targets = [
      %{"DATABASE_DIRECT_URL" => @direct},
      %{
        "ASH_PLATFORM_DATABASE_TARGET_MODE" => "production",
        "ASH_PLATFORM_DATABASE_CLUSTER_ID" => "dzx6qo6xqzvojpv5",
        "DATABASE_DIRECT_URL" => @direct
      },
      production_env(%{
        "ASH_PLATFORM_DATABASE_CLUSTER_ID" => "wrong",
        "DATABASE_DIRECT_URL" => @direct
      }),
      production_env(%{"FLY_APP_NAME" => "platform-phx", "DATABASE_DIRECT_URL" => @direct}),
      production_env(%{
        "FLY_APP_NAME" => "regents-pg-test",
        "DATABASE_DIRECT_URL" => @direct
      }),
      production_env(%{
        "ASH_PLATFORM_DATABASE_TARGET_MODE" => "rehearsal",
        "DATABASE_DIRECT_URL" => @direct
      })
    ]

    for values <- invalid_targets do
      assert_raise RuntimeError,
                   "database migration requires production mode for cluster dzx6qo6xqzvojpv5 named regents-platform-prod",
                   fn -> DatabaseConfig.release_config!(env(values)) end
    end
  end

  test "release rejects production identity embedded or encoded in direct URLs" do
    for url <- [
          "postgresql://user:secret@platform-phx.example.test/db",
          "postgresql://user:secret@safe.example.test/regents-pg-test",
          "postgresql://nvwq9ozp9ye03kl1:secret@safe.example.test/db"
        ] do
      error =
        assert_raise RuntimeError, fn ->
          DatabaseConfig.release_config!(env(production_env(%{"DATABASE_DIRECT_URL" => url})))
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

  test "development accepts the exact production target and selects pooled access" do
    assert DatabaseConfig.runtime_config!(
             :dev,
             env(%{
               "ASH_PLATFORM_DATABASE_CLUSTER_ID" => "dzx6qo6xqzvojpv5",
               "ASH_PLATFORM_DATABASE_CLUSTER_NAME" => "regents-platform-prod",
               "DATABASE_POOLED_URL" => @pooled,
               "DATABASE_DIRECT_URL" => @direct
             })
           ) == [url: @pooled, socket_options: @socket_options]
  end

  test "development rejects incomplete, wrong, production, and deployed-app targets" do
    invalid_targets = [
      %{"ASH_PLATFORM_DATABASE_CLUSTER_ID" => "dzx6qo6xqzvojpv5"},
      %{
        "ASH_PLATFORM_DATABASE_CLUSTER_ID" => "wrong",
        "ASH_PLATFORM_DATABASE_CLUSTER_NAME" => "regents-platform-prod"
      },
      %{
        "ASH_PLATFORM_DATABASE_CLUSTER_ID" => "dzx6qo6xqzvojpv5",
        "ASH_PLATFORM_DATABASE_CLUSTER_NAME" => "regents-pg-test"
      },
      %{"FLY_APP_NAME" => "platform-phx"}
    ]

    for values <- invalid_targets do
      assert_raise RuntimeError,
                   "remote database access requires cluster dzx6qo6xqzvojpv5 named regents-platform-prod",
                   fn -> DatabaseConfig.runtime_config!(:dev, env(values)) end
    end
  end

  test "canonical URLs reject production identity in hostname, database, or username" do
    malicious_urls = [
      "postgresql://user:secret@regents-pg-test.example.test/db",
      "postgresql://user:secret@safe.example.test/regents-pg-test",
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
          {fn getenv -> DatabaseConfig.release_config!(env(production_env_from(getenv))) end,
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
    remote = env(production_env(%{"DATABASE_POOLED_URL" => @pooled}))
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
        env(production_env(%{"DATABASE_POOLED_URL" => @mpg_pooled}))
      )

    effective = effective_repo_config(config)

    assert effective[:url] == nil
    assert effective[:hostname] == "pgbouncer.dzx6qo6xqzvojpv5.flympg.net"
    assert effective[:socket_options] == @socket_options
    assert effective[:prepare] == :unnamed
    assert_verified_tls(effective[:ssl], "pgbouncer.dzx6qo6xqzvojpv5.flympg.net")
  end

  test "Fly MPG direct access uses verified TLS without pooled prepare mode" do
    config =
      DatabaseConfig.release_config!(env(production_env(%{"DATABASE_DIRECT_URL" => @mpg_direct})))

    effective = effective_repo_config(config)

    assert effective[:url] == nil
    assert effective[:hostname] == "direct.dzx6qo6xqzvojpv5.flympg.net"
    assert effective[:socket_options] == @socket_options
    refute Keyword.has_key?(effective, :prepare)
    assert_verified_tls(effective[:ssl], "direct.dzx6qo6xqzvojpv5.flympg.net")
  end

  test "Fly MPG runtime options override the compiled sentinel port when URLs omit it" do
    compiled_config = Config.Reader.read!("config/config.exs", env: :prod, target: :host)
    assert get_in(compiled_config, [:ash_platform, AshPlatform.Repo])[:port] == 1

    configs = [
      DatabaseConfig.runtime_config!(
        :prod,
        env(%{
          "DATABASE_POOLED_URL" =>
            "postgresql://user:secret@direct.dzx6qo6xqzvojpv5.flympg.net/ash_platform"
        })
      ),
      DatabaseConfig.runtime_config!(
        :dev,
        env(
          production_env(%{
            "DATABASE_POOLED_URL" =>
              "postgresql://user:secret@pgbouncer.dzx6qo6xqzvojpv5.flympg.net/ash_platform"
          })
        )
      )
    ]

    for config <- configs do
      merged =
        Config.Reader.merge(
          compiled_config,
          ash_platform: [{AshPlatform.Repo, config}]
        )

      assert config[:port] == 5432
      merged_repo = get_in(merged, [:ash_platform, AshPlatform.Repo])
      assert merged_repo[:port] == 5432
      assert effective_repo_config(merged_repo)[:port] == 5432
    end
  end

  test "Fly MPG direct and PgBouncer URLs reject non-PostgreSQL ports without credentials" do
    cases = [
      {fn url ->
         DatabaseConfig.runtime_config!(:prod, env(%{"DATABASE_POOLED_URL" => url}))
       end,
       "postgresql://direct-user:sentinel-secret@direct.dzx6qo6xqzvojpv5.flympg.net:6543/ash_platform"},
      {fn url ->
         DatabaseConfig.runtime_config!(
           :dev,
           env(production_env(%{"DATABASE_POOLED_URL" => url}))
         )
       end,
       "postgresql://pooled-user:sentinel-secret@pgbouncer.dzx6qo6xqzvojpv5.flympg.net:6543/ash_platform"}
    ]

    for {configure, url} <- cases do
      error = assert_raise RuntimeError, fn -> configure.(url) end

      assert Exception.message(error) ==
               "DATABASE_POOLED_URL must be a valid PostgreSQL URL for the approved target"

      refute Exception.message(error) =~ "sentinel-secret"
      refute Exception.message(error) =~ url
    end
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
            env(production_env(%{"DATABASE_POOLED_URL" => url}))
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
        env(production_env(%{"DATABASE_POOLED_URL" => mpg_url}))
      )

    assert_verified_tls(mpg[:ssl], "custom.cluster.flympg.net")
    refute Keyword.has_key?(mpg, :prepare)

    for url <- [
          "postgresql://user:secret@evilflympg.net:5432/ash_platform",
          "postgresql://user:secret@flympg.net:5432/ash_platform"
        ] do
      assert DatabaseConfig.runtime_config!(
               :dev,
               env(production_env(%{"DATABASE_POOLED_URL" => url}))
             ) == [url: url, socket_options: @socket_options]
    end
  end

  test "production and release reject every host except the exact direct cluster hostname" do
    invalid_hosts = [
      "pgbouncer.dzx6qo6xqzvojpv5.flympg.net",
      "direct.another-cluster.flympg.net",
      "flympg.net",
      "direct.dzx6qo6xqzvojpv5.flympg.net.attacker.example",
      "direct.dzx6qo6xqzvojpv5.evilflympg.net"
    ]

    for host <- invalid_hosts,
        {selector, variable} <- [
          {fn url ->
             DatabaseConfig.runtime_config!(:prod, env(%{"DATABASE_POOLED_URL" => url}))
           end, "DATABASE_POOLED_URL"},
          {fn url ->
             DatabaseConfig.release_config!(env(production_env(%{"DATABASE_DIRECT_URL" => url})))
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
      "postgresql://user:secret@DIRECT.DZX6QO6XQZVOJPV5.FLYMPG.NET:5432/ash_platform"

    effective =
      :prod
      |> DatabaseConfig.runtime_config!(env(%{"DATABASE_POOLED_URL" => uppercase}))
      |> effective_repo_config()

    assert effective[:hostname] == "direct.dzx6qo6xqzvojpv5.flympg.net"
    assert_verified_tls(effective[:ssl], "direct.dzx6qo6xqzvojpv5.flympg.net")
    refute Keyword.has_key?(effective, :prepare)
  end

  test "a missing or unrecognized deployment role stops production before any URL is read" do
    for role <- [nil, "", "prod", "PRODUCTION", "Staging", "staging ", "rehearsal"] do
      getenv = fn
        @role -> role
        "DATABASE_POOLED_URL" -> flunk("production runtime read a database URL without a role")
        "DATABASE_DIRECT_URL" -> flunk("the release path read a database URL without a role")
        _name -> nil
      end

      assert_raise RuntimeError, @role_error, fn ->
        DatabaseConfig.runtime_config!(:prod, getenv)
      end

      assert_raise RuntimeError, @role_error, fn -> DatabaseConfig.release_config!(getenv) end
    end
  end

  test "development and test never read the deployment role" do
    getenv = fn
      @role -> flunk("a local environment read the deployment role")
      "USER" -> "local-user"
      _name -> nil
    end

    assert DatabaseConfig.runtime_config!(:test, getenv) == nil
    assert DatabaseConfig.runtime_config!(:dev, getenv)[:database] == "ash_platform_dev"
  end

  test "the staging role admits exactly the two staging hosts, with no production ceremony" do
    for url <- [@staging_flycast, @staging_internal] do
      runtime =
        DatabaseConfig.runtime_config!(:prod, staging_env(%{"DATABASE_POOLED_URL" => url}))

      release = DatabaseConfig.release_config!(staging_env(%{"DATABASE_DIRECT_URL" => url}))

      assert runtime == [url: url, socket_options: @socket_options]
      assert release == [url: url, socket_options: @socket_options]
    end
  end

  test "the staging role normalizes an admitted host before Repo parsing" do
    uppercase = "postgresql://user:secret@REGENTS-STAGING-DB.FLYCAST:5432/ash_platform"

    for config <- [
          DatabaseConfig.runtime_config!(
            :prod,
            staging_env(%{"DATABASE_POOLED_URL" => uppercase})
          ),
          DatabaseConfig.release_config!(staging_env(%{"DATABASE_DIRECT_URL" => uppercase}))
        ] do
      assert effective_repo_config(config)[:hostname] == "regents-staging-db.flycast"
    end
  end

  test "the staging role refuses production hosts, the production cluster, and every identity" do
    refused = [
      @mpg_direct,
      @mpg_pooled,
      "postgresql://user:secret@custom.cluster.flympg.net:5432/ash_platform",
      "postgresql://user:secret@flympg.net:5432/ash_platform",
      "postgresql://user:secret@regents-staging-db.flycast:5432/nvwq9ozp9ye03kl1",
      "postgresql://nvwq9ozp9ye03kl1:secret@regents-staging-db.flycast:5432/ash_platform",
      "postgresql://user:secret@regents-staging-db.flycast:5432/regents-pg-test",
      "postgresql://user:secret@regents-staging-db.flycast:5432/platform-phx",
      "postgresql://user:secret@regents-staging-db.flycast:5432/regents-sh-web",
      "postgresql://regents-sh-web:secret@regents-staging-db.flycast:5432/ash_platform",
      "postgresql://user:secret@regents-sh-web:5432/ash_platform",
      "postgresql://user:secret@regents-staging-db.flycast:5432/direct.dzx6qo6xqzvojpv5.flympg.net",
      "postgresql://direct.dzx6qo6xqzvojpv5.flympg.net:secret@regents-staging-db.flycast:5432/ash_platform",
      "postgresql://user:secret@regents-staging-db.flycast.attacker.example:5432/ash_platform",
      "postgresql://user:secret@other-regents-staging-db.flycast:5432/ash_platform",
      "postgresql://user:secret@regents-staging-db.example.test:5432/ash_platform"
    ]

    for url <- refused,
        {selector, variable} <- [
          {fn value ->
             DatabaseConfig.runtime_config!(:prod, staging_env(%{"DATABASE_POOLED_URL" => value}))
           end, "DATABASE_POOLED_URL"},
          {fn value ->
             DatabaseConfig.release_config!(staging_env(%{"DATABASE_DIRECT_URL" => value}))
           end, "DATABASE_DIRECT_URL"}
        ] do
      error = assert_raise RuntimeError, fn -> selector.(url) end

      assert Exception.message(error) ==
               "#{variable} must be a valid PostgreSQL URL for the approved target"

      refute Exception.message(error) =~ "secret"
    end
  end

  # The staging hostname fixes the venue just as the production one does, so the
  # staging role admits no query options and no port but PostgreSQL's either.
  test "the staging role refuses URL queries and non-PostgreSQL ports on both hosts" do
    queried =
      for base <- [@staging_flycast, @staging_internal],
          query <- ["ssl=false", "s%73l=false", "prepare=named", "hostname=attacker.example"],
          do: "#{base}?#{query}"

    refused =
      queried ++
        [
          "postgresql://staging_user:staging-secret@regents-staging-db.flycast:6543/ash_platform",
          "postgresql://staging_user:staging-secret@regents-staging-db.internal:6543/ash_platform"
        ]

    for url <- refused,
        {selector, variable} <- [
          {fn value ->
             DatabaseConfig.runtime_config!(:prod, staging_env(%{"DATABASE_POOLED_URL" => value}))
           end, "DATABASE_POOLED_URL"},
          {fn value ->
             DatabaseConfig.release_config!(staging_env(%{"DATABASE_DIRECT_URL" => value}))
           end, "DATABASE_DIRECT_URL"}
        ] do
      error = assert_raise RuntimeError, fn -> selector.(url) end

      assert Exception.message(error) ==
               "#{variable} must be a valid PostgreSQL URL for the approved target"

      refute Exception.message(error) =~ "staging-secret"
    end
  end

  test "the production role refuses the staging database hosts on both paths" do
    for url <- [@staging_flycast, @staging_internal] do
      assert_raise RuntimeError,
                   "DATABASE_POOLED_URL must be a valid PostgreSQL URL for the approved target",
                   fn ->
                     DatabaseConfig.runtime_config!(:prod, env(%{"DATABASE_POOLED_URL" => url}))
                   end

      assert_raise RuntimeError,
                   "DATABASE_DIRECT_URL must be a valid PostgreSQL URL for the approved target",
                   fn ->
                     DatabaseConfig.release_config!(
                       env(production_env(%{"DATABASE_DIRECT_URL" => url}))
                     )
                   end
    end
  end

  # Production runs as the Fly application regents-sh-web, so that name belongs to
  # staging's refusal list alone. If the production role evaluated it anywhere,
  # this deployment -- the real one -- would stop on its own name.
  test "the production role reads regents-sh-web exactly as it did before staging existed" do
    named_url =
      "postgresql://user:secret@direct.dzx6qo6xqzvojpv5.flympg.net:5432/regents-sh-web"

    assert DatabaseConfig.release_config!(
             env(
               production_env(%{
                 "FLY_APP_NAME" => "regents-sh-web",
                 "DATABASE_DIRECT_URL" => @mpg_direct
               })
             )
           ) ==
             DatabaseConfig.release_config!(
               env(production_env(%{"DATABASE_DIRECT_URL" => @mpg_direct}))
             )

    assert DatabaseConfig.runtime_config!(
             :prod,
             env(%{"FLY_APP_NAME" => "regents-sh-web", "DATABASE_POOLED_URL" => @mpg_direct})
           ) ==
             DatabaseConfig.runtime_config!(:prod, env(%{"DATABASE_POOLED_URL" => @mpg_direct}))

    for {selector, variable} <- [
          {&DatabaseConfig.runtime_config!(:prod, &1), "DATABASE_POOLED_URL"},
          {&DatabaseConfig.release_config!/1, "DATABASE_DIRECT_URL"}
        ] do
      config = selector.(env(production_env(%{variable => named_url})))

      assert effective_repo_config(config)[:hostname] == "direct.dzx6qo6xqzvojpv5.flympg.net"
    end

    assert DatabaseConfig.runtime_config!(:dev, env(%{"FLY_APP_NAME" => "regents-sh-web"})) == [
             username: nil,
             password: nil,
             hostname: "127.0.0.1",
             port: 5432,
             database: "ash_platform_dev",
             pool_size: 2
           ]
  end

  # Every deployed path names its venue. These cases exercise the production
  # role unless they say otherwise; the role's own admission is proven by the
  # deployment-role cases above.
  defp env(values), do: &Map.get(Map.put_new(values, @role, "production"), &1)

  defp staging_env(values), do: env(Map.put(values, @role, "staging"))

  defp production_env(overrides) do
    Map.merge(
      %{
        "ASH_PLATFORM_DATABASE_TARGET_MODE" => "production",
        "ASH_PLATFORM_DATABASE_CLUSTER_ID" => "dzx6qo6xqzvojpv5",
        "ASH_PLATFORM_DATABASE_CLUSTER_NAME" => "regents-platform-prod"
      },
      overrides
    )
  end

  defp production_env_from(getenv) do
    production_env(%{"DATABASE_DIRECT_URL" => getenv.("DATABASE_DIRECT_URL")})
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
