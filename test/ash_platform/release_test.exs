defmodule AshPlatform.ReleaseTest do
  use ExUnit.Case, async: true

  @direct "postgresql://direct_user:direct-secret@direct.nvwq9ozp9ye03kl1.flympg.net:5432/ash_platform"

  test "migration configuration uses only direct access" do
    getenv = fn
      "DATABASE_DIRECT_URL" -> @direct
      "ASH_PLATFORM_DATABASE_TARGET_MODE" -> "rehearsal"
      "ASH_PLATFORM_DATABASE_CLUSTER_ID" -> "nvwq9ozp9ye03kl1"
      "ASH_PLATFORM_DATABASE_CLUSTER_NAME" -> "regents-pg-test"
      "DATABASE_POOLED_URL" -> flunk("migration configuration read pooled access")
      _name -> nil
    end

    assert AshPlatform.Release.migration_config!(getenv) == [
             ssl: [
               verify: :verify_peer,
               cacerts: :public_key.cacerts_get(),
               server_name_indication: ~c"direct.nvwq9ozp9ye03kl1.flympg.net",
               customize_hostname_check: [
                 match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
               ]
             ],
             port: 5432,
             url: @direct,
             socket_options: [:inet6]
           ]
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
