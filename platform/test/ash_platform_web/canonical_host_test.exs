defmodule AshPlatformWeb.CanonicalHostTest do
  use AshPlatformWeb.ConnCase, async: true

  alias AshPlatformWeb.Endpoint

  # A page opened on www. could never connect back to the server, so Stake
  # showed "Connect wallet" to signed-in visitors and Redeem never loaded.
  test "a visit to the www. address lands on the same page at the site's own address" do
    for path <- ["/stake", "/redeem?collection=animata_ii&token=7", "/"] do
      conn = get(%{build_conn() | host: "www." <> Endpoint.host()}, path)

      assert conn.status == 301
      assert get_resp_header(conn, "location") == [Endpoint.url() <> path]
    end
  end

  test "a visit to the site's own address is served in place" do
    conn = get(%{build_conn() | host: Endpoint.host()}, "/stake")

    assert conn.status == 200
    assert get_resp_header(conn, "location") == []
  end
end
