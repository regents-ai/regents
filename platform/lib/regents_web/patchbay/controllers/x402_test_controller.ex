defmodule RegentsWeb.Patchbay.X402TestController do
  @moduledoc """
  The Wallet Bench's paid-call test page. `RegentsWeb.Patchbay.Plugs.X402Test` stands
  in front of it, so this answer is reached only by a request that paid, and
  is sent only once that payment has settled.
  """

  use RegentsWeb, :controller

  def preflight(conn, _params) do
    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_header("access-control-allow-methods", "GET, HEAD, OPTIONS")
    |> put_resp_header(
      "access-control-allow-headers",
      "Payment-Signature, X-Payment, Authorization, Content-Type"
    )
    |> put_resp_header(
      "access-control-expose-headers",
      "PAYMENT-REQUIRED, PAYMENT-RESPONSE, X-PAYMENT-RESPONSE"
    )
    |> put_resp_header("access-control-max-age", "600")
    |> put_resp_header("vary", "Origin, Access-Control-Request-Headers")
    |> send_resp(:no_content, "")
  end

  def show(conn, _params) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_header(
      "access-control-expose-headers",
      "PAYMENT-REQUIRED, PAYMENT-RESPONSE, X-PAYMENT-RESPONSE"
    )
    |> json(%{message: "test passed"})
  end
end
