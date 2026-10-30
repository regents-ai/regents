defmodule RegentsWeb.CreditsRefundsLiveTest do
  use RegentsWeb.ConnCase, async: true

  alias RegentsWeb.CreditsRefundRules

  test "CREDITS_REFUNDS: people and agents read the same refund rules", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/credits/refunds")
    assert has_element?(view, "#credits-refund-rules h1")
    assert has_element?(view, "#credits-refund-rules a[href='mailto:support@regents.sh']")

    markdown =
      build_conn()
      |> put_req_header("accept", "text/markdown")
      |> get("/credits/refunds")
      |> response(200)

    assert markdown == CreditsRefundRules.markdown()
  end
end
