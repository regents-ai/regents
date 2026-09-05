defmodule AshPlatformWeb.RouteHandoffTest do
  use ExUnit.Case, async: true

  alias AshPlatformWeb.RouteCatalog

  @json_path "priv/handoff/founder-shell-route-catalog.json"
  @digest_path "priv/handoff/founder-shell-route-catalog.sha256"

  test "materialized Design handoff exactly matches the route catalog owner" do
    handoff = RouteCatalog.design_handoff()

    assert File.read!(@json_path) == handoff.json
    assert File.read!(@digest_path) == handoff.digest <> "\n"
  end
end
