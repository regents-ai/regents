defmodule AshPlatformWeb.LegalControllerTest do
  use AshPlatformWeb.ConnCase, async: true

  test "PRIVACY: the policy is on /privacy and does not carry draft placeholders" do
    conn = get(build_conn(), "/privacy")
    body = html_response(conn, 200)

    assert body =~ "Regents Labs Privacy Policy"
    assert body =~ "privacy@regents.sh"
    assert body =~ "mailto:privacy@regents.sh"
    refute body =~ "INSERT"
    refute body =~ "billing-readiness"
  end

  test "TERMS: the terms are on /terms and do not carry draft placeholders" do
    conn = get(build_conn(), "/terms")
    body = html_response(conn, 200)

    assert body =~ "Regents Labs Terms of Use"
    assert body =~ "legal@regents.sh"
    assert body =~ "mailto:legal@regents.sh"
    refute body =~ "INSERT"
  end
end
