defmodule RegentsWeb.MetricsTest do
  use RegentsWeb.ConnCase, async: false

  alias RegentsWeb.Metrics

  test "PRIVATE_SCRAPE: the metrics listener serves the bounded Privy browser failure counter" do
    :telemetry.execute([:regents, :privy, :browser_failure], %{count: 1}, %{
      reason: "provider_error"
    })

    conn = Metrics.call(Plug.Test.conn(:get, "/metrics"), [])

    assert conn.status == 200
    assert conn.resp_body =~ ~s(regents_privy_browser_failure_total{reason="provider_error"})
    assert Plug.Conn.get_resp_header(conn, "content-type") == ["text/plain; charset=utf-8"]
  end

  defmodule RefusingNode do
    def post(_url, options) do
      case options[:json].method do
        "eth_chainId" -> {:error, %Req.TransportError{reason: :timeout}}
        "eth_blockNumber" -> {:ok, %{status: 503, body: ""}}
        "eth_call" -> {:ok, %{status: 200, body: %{"error" => %{"code" => -32_000}}}}
      end
    end
  end

  # Sentinel reads health_chain_request_failures_total from every site.
  test "every chain request that got no answer is counted by method, class, chain and scope" do
    previous = Application.get_env(:regents, :wallet_http_client)
    Application.put_env(:regents, :wallet_http_client, RefusingNode)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:regents, :wallet_http_client, previous),
        else: Application.delete_env(:regents, :wallet_http_client)
    end)

    ExUnit.CaptureLog.capture_log(fn ->
      Regents.WalletActions.Rpc.request("eth_chainId", [], scope: "points")
      Regents.WalletActions.Rpc.request("eth_blockNumber", [], chain_id: 1, scope: "wallet_steps")
      Regents.WalletActions.Rpc.answer("eth_call", [])
    end)

    body = Metrics.call(Plug.Test.conn(:get, "/metrics"), []).resp_body

    for line <- [
          ~s(health_chain_request_failures_total{chain_id="8453",class="timeout",method="eth_chainId",scope="points"}),
          ~s(health_chain_request_failures_total{chain_id="1",class="http_503",method="eth_blockNumber",scope="wallet_steps"}),
          ~s(health_chain_request_failures_total{chain_id="8453",class="rpc",method="eth_call",scope="wallet"})
        ],
        do: assert(body =~ line, line)
  end

  test "the metrics listener answers nothing else" do
    assert Metrics.call(Plug.Test.conn(:get, "/healthz"), []).status == 404
    assert Metrics.call(Plug.Test.conn(:post, "/metrics"), []).status == 404
  end

  test "PUBLIC_SITE: the public site never serves metrics, and health stays open", %{conn: conn} do
    assert conn |> get("/metrics") |> response(404)
    assert conn |> get("/healthz") |> response(200)
  end
end
