defmodule AshPlatform.ReleaseTest do
  use ExUnit.Case, async: true

  @direct_host "direct.nvwq9ozp9ye03kl1.flympg.net"
  @direct "postgresql://direct_user:direct-secret@#{@direct_host}:5432/ash_platform"

  test "migration configuration uses only direct access" do
    getenv = fn
      "DATABASE_DIRECT_URL" -> @direct
      "ASH_PLATFORM_DATABASE_TARGET_MODE" -> "rehearsal"
      "ASH_PLATFORM_DATABASE_CLUSTER_ID" -> "nvwq9ozp9ye03kl1"
      "ASH_PLATFORM_DATABASE_CLUSTER_NAME" -> "regents-pg-test"
      "DATABASE_POOLED_URL" -> flunk("migration configuration read pooled access")
      _name -> nil
    end

    config = AshPlatform.Release.migration_config!(getenv)
    assert config[:url] == @direct

    {url, explicit} = Keyword.pop(config, :url)
    effective = Keyword.merge(explicit, Ecto.Repo.Supervisor.parse_url(url))

    assert effective[:hostname] == @direct_host
    assert effective[:socket_options] == [:inet6]
    refute Keyword.has_key?(effective, :prepare)
    assert effective[:ssl][:verify] == :verify_peer
    assert effective[:ssl][:server_name_indication] == String.to_charlist(@direct_host)
    assert is_list(effective[:ssl][:cacerts]) and effective[:ssl][:cacerts] != []

    assert is_function(
             get_in(effective, [:ssl, :customize_hostname_check, :match_fun]),
             2
           )
  end

  test "migration configuration fails closed without an explicit rehearsal target" do
    assert_raise RuntimeError,
                 "database migration requires rehearsal mode for cluster nvwq9ozp9ye03kl1 named regents-pg-test",
                 fn ->
                   AshPlatform.Release.migration_config!(fn _name -> nil end)
                 end
  end

  test "PKG-MIGRATION launcher invokes the guarded release migration without printing variables" do
    script = File.read!("rel/overlays/bin/migrate")

    assert script =~ "AshPlatform.Release.migrate()"
    assert script =~ "ASH_PLATFORM_RELEASE_COMMAND=migrate"
    refute script =~ "ASH_PLATFORM_DATABASE_TARGET_MODE="
    refute script =~ "echo"
    refute script =~ "DATABASE_POOLED_URL"
    refute script =~ "DATABASE_DIRECT_URL"
  end
end
