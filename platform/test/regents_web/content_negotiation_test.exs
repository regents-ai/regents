defmodule RegentsWeb.ContentNegotiationTest do
  # Adapted from ash-template 574a5bf: content_negotiation_test.exs.
  use ExUnit.Case, async: false

  import Phoenix.ConnTest, only: [assert_error_sent: 2]
  import Plug.Conn, only: [get_resp_header: 2, put_req_header: 3]
  import Plug.Test, only: [conn: 2]

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Regents.Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
    open? = Application.fetch_env!(:regents, :app_surfaces)
    Application.put_env(:regents, :app_surfaces, true)
    on_exit(fn -> Application.put_env(:regents, :app_surfaces, open?) end)
  end

  # Regression: allowing JSON on a LiveView route sends {:safe, html} to Jason
  # and crashes. Both ways of selecting that format must fail before rendering.
  test "HTML pages reject JSON selected by Accept or _format" do
    assert request("/start", "application/json").status == 406
    assert_error_sent(406, fn -> request("/start?_format=json", "text/html") end)
  end

  test "a browser or an Accept header with an HTML fallback still gets LiveView HTML" do
    for accept <- ["text/html", "application/json, text/html;q=0.9"] do
      response = request("/start", accept)
      assert response.status == 200
      assert [content_type] = get_resp_header(response, "content-type")
      assert content_type =~ "text/html"
      assert response.resp_body =~ "data-phx-main"
    end
  end

  # Browser fetch uses */* here. Refusing JSON page rendering must not turn the
  # existing session response into HTML or require a signed-in account to read it.
  test "the existing session fetch still returns JSON" do
    response = request("/auth/session", "*/*")
    assert response.status == 200
    assert [content_type] = get_resp_header(response, "content-type")
    assert content_type =~ "application/json"
    assert %{"authenticated" => false} = Jason.decode!(response.resp_body)
  end

  defp request(path, accept) do
    :get
    |> conn(path)
    |> put_req_header("accept", accept)
    |> RegentsWeb.Endpoint.call(RegentsWeb.Endpoint.init([]))
  end
end
