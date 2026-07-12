defmodule AshPlatformWeb.TechtreeNodeControllerTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.Actors.System
  alias AshPlatform.Techtree

  defmodule FailingTechtree do
    def list_public_nodes(actor: nil), do: {:error, {:sentinel, "private details"}}
  end

  test "GET returns the honest public node list through the declared route", %{conn: conn} do
    Ecto.Adapters.SQL.query!(AshPlatform.Repo, "DELETE FROM techtree.notebook_artifacts", [])
    Ecto.Adapters.SQL.query!(AshPlatform.Repo, "DELETE FROM techtree.nodes", [])

    conn = get(conn, "/api/techtree/v1/tree/nodes")

    assert json_response(conn, 200) == %{"data" => []}

    assert Enum.any?(AshPlatformWeb.Router.__routes__(), fn route ->
             route.verb == :get and route.path == "/api/techtree/v1/tree/nodes" and
               route.plug == AshPlatformWeb.TechtreeNodeController and
               route.plug_opts == :index
           end)
  end

  test "GET rejects every query parameter", %{conn: conn} do
    conn = get(conn, "/api/techtree/v1/tree/nodes?limit=1")

    assert json_response(conn, 400) == %{
             "error" => %{
               "code" => "invalid_request",
               "message" => "Query parameters are not supported."
             }
           }
  end

  test "GET hides internal failures behind the canonical error envelope", %{conn: conn} do
    response =
      conn
      |> Plug.Conn.put_private(:techtree_node_controller_techtree, FailingTechtree)
      |> get("/api/techtree/v1/tree/nodes")

    assert json_response(response, 500) == %{
             "error" => %{
               "code" => "internal_error",
               "message" => "The request could not be completed."
             }
           }

    body = response.resp_body
    refute body =~ "sentinel"
    refute body =~ "private details"
  end

  test "GET returns only canonical fields in newest-first order", %{conn: conn} do
    tree = Techtree.get_tree_by_slug!("skill-training-lab")

    older =
      Techtree.import_public_node!(tree.id, "Older", "Public summary", "sha256:older",
        actor: %System{}
      )

    newer =
      Techtree.import_public_node!(tree.id, "Newer", nil, nil, actor: %System{})

    conn = get(conn, "/api/techtree/v1/tree/nodes")

    assert %{"data" => [first, second | _baseline]} = json_response(conn, 200)
    assert first["id"] == newer.id
    assert second["id"] == older.id

    assert Map.keys(first) |> Enum.sort() ==
             ~w(id payload_hash published_at summary title tree_id)

    assert first == %{
             "id" => newer.id,
             "tree_id" => newer.tree_id,
             "title" => "Newer",
             "summary" => nil,
             "payload_hash" => nil,
             "published_at" => DateTime.to_iso8601(newer.published_at)
           }
  end

  test "cookies and bearer headers do not affect the public result", %{conn: conn} do
    tree = Techtree.get_tree_by_slug!("question-forge-metaskills")

    node = Techtree.import_public_node!(tree.id, "Public", nil, nil, actor: %System{})

    anonymous = conn |> get("/api/techtree/v1/tree/nodes") |> json_response(200)

    credentialed =
      conn
      |> put_req_cookie("_ash_platform_key", "not-a-session")
      |> put_req_header("authorization", "Bearer not-an-agent-token")
      |> get("/api/techtree/v1/tree/nodes")
      |> json_response(200)

    assert anonymous == credentialed
    assert anonymous["data"] |> hd() |> Map.fetch!("id") == node.id
  end
end
