defmodule RegentsWeb.ContentSecurityPolicyTest do
  use RegentsWeb.ConnCase, async: true

  alias RegentsWeb.ContentSecurityPolicy

  test "PAGE_POLICY: pages that can sign someone in carry the sign-in policy", %{conn: conn} do
    for path <- ~w(/ /stake /articles /privacy) do
      response = get(conn, path)

      assert get_resp_header(response, "content-security-policy") == [
               ContentSecurityPolicy.sign_in()
             ]

      assert get_resp_header(response, "referrer-policy") == ["strict-origin-when-cross-origin"]
    end
  end

  test "PAGE_POLICY: reading pages carry the strict policy and send no referrer", %{conn: conn} do
    for path <- ~w(/docs /about /contact) do
      response = get(conn, path)

      assert get_resp_header(response, "content-security-policy") == [
               ContentSecurityPolicy.reading()
             ]

      assert get_resp_header(response, "referrer-policy") == ["no-referrer"]
    end
  end

  # An image, icon or script opened on its own is a page that may do nothing.
  test "STATIC_POLICY: files served as they are say they may do nothing", %{conn: conn} do
    for path <- ~w(/images/share/home.png /favicon.ico /api-contract.openapiv3.yaml) do
      response = get(conn, path)

      assert response.status == 200

      assert get_resp_header(response, "content-security-policy") ==
               ["default-src 'none'; frame-ancestors 'none'"]

      assert get_resp_header(response, "x-frame-options") == ["DENY"]
      assert get_resp_header(response, "referrer-policy") == ["no-referrer"]
      assert get_resp_header(response, "x-content-type-options") == ["nosniff"]
    end
  end

  test "PAGE_POLICY: only sign-in pages admit Privy, and neither page may be framed" do
    refute ContentSecurityPolicy.reading() =~ "auth.privy.io"
    assert ContentSecurityPolicy.sign_in() =~ "frame-src https://auth.privy.io"
    # Privy serves the Telegram sign-in script itself.
    assert ContentSecurityPolicy.sign_in() =~ "script-src 'self' https://auth.privy.io"

    for policy <- [ContentSecurityPolicy.reading(), ContentSecurityPolicy.sign_in()] do
      assert policy =~ "default-src 'none'"
      assert policy =~ "frame-ancestors 'none'"
      refute policy =~ "unsafe-eval"
    end
  end
end
