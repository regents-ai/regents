defmodule RegentsWeb.ContentSecurityPolicyTest do
  use RegentsWeb.ConnCase, async: true

  alias RegentsWeb.ContentSecurityPolicy

  test "PAGE_POLICY: pages that can sign someone in carry the sign-in policy", %{conn: conn} do
    for path <- ~w(/ /stake /blog /privacy) do
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
