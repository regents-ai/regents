defmodule AshPlatformWeb.TechtreeReadControllerTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.Actors.System
  alias AshPlatform.Techtree
  alias AshPlatform.Techtree.{Edge, Node}

  defmodule ErrorTechtree do
    def get_public_node(_id, actor: nil), do: {:error, Process.get(:techtree_read_error)}
  end

  test "lists public trees through the declared anonymous route", %{conn: conn} do
    tree = tree!("trees")

    response = get(conn, "/api/techtree/v1/trees")

    assert %{"data" => trees} = json_response(response, 200)

    assert %{
             "id" => tree.id,
             "slug" => tree.slug,
             "name" => tree.name,
             "description" => tree.description
           } in trees
  end

  test "tree-scoped pages never fall back to nodes from another tree", %{conn: conn} do
    empty_tree = tree!("empty")
    other_tree = tree!("other")

    other_node =
      Techtree.import_public_node!(other_tree.id, "Other tree node", nil, nil, actor: %System{})

    response = get(conn, "/api/techtree/v1/trees/#{empty_tree.slug}/nodes")

    assert json_response(response, 200) == %{
             "data" => [],
             "edges" => [],
             "next_cursor" => nil
           }

    refute response.resp_body =~ other_node.id
  end

  test "cursor pagination uses the stable id tiebreak and stays duplicate-free after an insert",
       %{
         conn: conn
       } do
    tree = tree!("pagination")

    original_nodes =
      for title <- ["First", "Second", "Third"] do
        Techtree.import_public_node!(tree.id, title, nil, nil, actor: %System{})
      end

    same_time = ~U[2030-01-01 00:00:00.000000Z]
    Enum.each(original_nodes, &set_published_at(&1, same_time))
    expected_ids = original_nodes |> Enum.map(& &1.id) |> Enum.sort()

    first_page = get_page(conn, tree.slug, nil, 1)
    assert [first_id] = page_ids(first_page)
    assert first_id == Enum.at(expected_ids, 0)
    assert is_binary(first_page["next_cursor"])

    inserted =
      Techtree.import_public_node!(tree.id, "Inserted between pages", nil, nil, actor: %System{})

    set_published_at(inserted, ~U[2031-01-01 00:00:00.000000Z])

    second_page = get_page(conn, tree.slug, first_page["next_cursor"], 1)
    third_page = get_page(conn, tree.slug, second_page["next_cursor"], 1)

    assert page_ids(second_page) == [Enum.at(expected_ids, 1)]
    assert page_ids(third_page) == [Enum.at(expected_ids, 2)]
    assert third_page["next_cursor"] == nil

    seen_ids = page_ids(first_page) ++ page_ids(second_page) ++ page_ids(third_page)
    assert seen_ids == expected_ids
    assert length(seen_ids) == length(Enum.uniq(seen_ids))
    refute inserted.id in seen_ids
  end

  test "cursors are bound to an existing node, timestamp, and requested tree", %{conn: conn} do
    source_tree = tree!("cursor-source")
    other_tree = tree!("cursor-other")

    for title <- ["Source one", "Source two"] do
      Techtree.import_public_node!(source_tree.id, title, nil, nil, actor: %System{})
    end

    source_page = get_page(conn, source_tree.slug, nil, 1)
    cursor = source_page["next_cursor"]
    assert is_binary(cursor)

    assert json_response(
             get(
               conn,
               "/api/techtree/v1/trees/#{other_tree.slug}/nodes?cursor=#{URI.encode_www_form(cursor)}"
             ),
             400
           ) == error_body("invalid_input", "The request input is invalid.")

    transplanted_tree_cursor =
      rewrite_cursor(cursor, fn [_tree_id, published_at, node_id] ->
        [other_tree.id, published_at, node_id]
      end)

    assert json_response(
             get(
               conn,
               "/api/techtree/v1/trees/#{other_tree.slug}/nodes?cursor=#{URI.encode_www_form(transplanted_tree_cursor)}"
             ),
             400
           ) == error_body("invalid_input", "The request input is invalid.")

    altered_timestamp_cursor =
      rewrite_cursor(cursor, fn [tree_id, _published_at, node_id] ->
        [tree_id, "2035-01-01T00:00:00Z", node_id]
      end)

    altered_node_cursor =
      rewrite_cursor(cursor, fn [tree_id, published_at, _node_id] ->
        [tree_id, published_at, Ash.UUID.generate()]
      end)

    for tampered_cursor <- [altered_timestamp_cursor, altered_node_cursor] do
      assert json_response(
               get(
                 conn,
                 "/api/techtree/v1/trees/#{source_tree.slug}/nodes?cursor=#{URI.encode_www_form(tampered_cursor)}"
               ),
               400
             ) == error_body("invalid_input", "The request input is invalid.")
    end
  end

  test "unpublished nodes and their edges are absent from every public read", %{conn: conn} do
    initial_public_count = Techtree.list_public_nodes!() |> length()
    tree = tree!("publication-boundary")

    published =
      Techtree.import_public_node!(tree.id, "Published node", nil, nil, actor: %System{})

    draft =
      Ash.Seed.seed!(Node, %{
        tree_id: tree.id,
        title: "Draft node",
        workflow_state: :draft
      })

    Ash.Seed.seed!(Edge, %{from_node_id: published.id, to_node_id: draft.id})

    assert published.workflow_state == :published
    assert draft.workflow_state == :draft
    assert not is_nil(draft.published_at)

    assert Enum.map(Techtree.list_tree_nodes!(tree.id), & &1.id) == [published.id]

    public_nodes = Techtree.list_public_nodes!()
    assert length(public_nodes) == initial_public_count + 1
    assert published.id in Enum.map(public_nodes, & &1.id)
    refute draft.id in Enum.map(public_nodes, & &1.id)

    assert {:ok, nil} = Techtree.get_public_node(draft.id)
    assert Techtree.list_tree_edges!(tree.id) == []

    primary_read_ids =
      AshPlatform.Techtree.Node
      |> Ash.read!(actor: nil, domain: Techtree)
      |> Enum.map(& &1.id)

    refute draft.id in primary_read_ids

    scoped =
      conn
      |> get("/api/techtree/v1/trees/#{tree.slug}/nodes")
      |> json_response(200)

    assert page_ids(scoped) == [published.id]
    assert scoped["edges"] == []

    assert json_response(get(conn, "/api/techtree/v1/nodes/#{draft.id}"), 404) ==
             error_body("not_found", "The requested public record was not found.")

    assert json_response(get(conn, "/api/techtree/v1/nodes/#{published.id}"), 200)["data"][
             "edges"
           ] == []

    legacy = conn |> get("/api/techtree/v1/tree/nodes") |> json_response(200)
    assert published.id in page_ids(legacy)
    refute draft.id in page_ids(legacy)
  end

  test "tree pages expose positions and both typed curation edge kinds", %{conn: conn} do
    tree = tree!("map")

    first =
      Techtree.import_public_node!(tree.id, "Positioned", nil, nil, actor: %System{})
      |> Techtree.update_node_layout!(12.5, -4.0, "benchmark_slice", actor: %System{})

    second = Techtree.import_public_node!(tree.id, "Related", nil, nil, actor: %System{})

    Techtree.create_edge!(first.id, second.id, actor: %System{})
    Techtree.create_edge!(second.id, first.id, %{kind: :related}, actor: %System{})

    response = get(conn, "/api/techtree/v1/trees/#{tree.slug}/nodes?limit=25")
    body = json_response(response, 200)

    positioned = Enum.find(body["data"], &(&1["id"] == first.id))
    assert positioned["position"] == %{"x" => 12.5, "y" => -4.0}
    assert positioned["display_kind"] == "benchmark_slice"
    assert Enum.map(body["edges"], & &1["kind"]) |> Enum.sort() == ["prerequisite", "related"]
  end

  test "node detail exposes recorded fields and omits unrecorded public detail", %{conn: conn} do
    tree = tree!("detail")

    node =
      Techtree.import_public_node!(tree.id, "Detailed node", "Public summary", "sha256:abc",
        actor: %System{}
      )
      |> Techtree.update_node_layout!(8.0, 13.0, "uplift_report", actor: %System{})

    related = Techtree.import_public_node!(tree.id, "Related node", nil, nil, actor: %System{})
    Techtree.create_edge!(node.id, related.id, %{kind: :related}, actor: %System{})

    response = get(conn, "/api/techtree/v1/nodes/#{node.id}")
    assert %{"data" => detail} = json_response(response, 200)

    assert detail == %{
             "id" => node.id,
             "tree_id" => tree.id,
             "kind" => "uplift_report",
             "title" => "Detailed node",
             "summary" => "Public summary",
             "payload_hash" => "sha256:abc",
             "base_mainnet_projection" => %{
               "chain_id" => 8453,
               "projection_status" => "not_started",
               "record_uid" => nil,
               "transaction_hash" => nil,
               "block_number" => nil
             },
             "position" => %{"x" => 8.0, "y" => 13.0},
             "edges" => [
               %{
                 "from_node_id" => node.id,
                 "to_node_id" => related.id,
                 "kind" => "related"
               }
             ],
             "published_at" => DateTime.to_iso8601(node.published_at)
           }

    for absent <-
          ~w(contributor_id lineage_node_ids capsule immutable_payloads evidence_projection evidence_state) do
      refute Map.has_key?(detail, absent)
    end
  end

  test "invalid input and honest absence are distinct", %{conn: conn} do
    tree = tree!("errors")

    for path <- [
          "/api/techtree/v1/trees?unexpected=true",
          "/api/techtree/v1/trees/INVALID/nodes",
          "/api/techtree/v1/trees/#{tree.slug}/nodes?limit=0",
          "/api/techtree/v1/trees/#{tree.slug}/nodes?limit=101",
          "/api/techtree/v1/trees/#{tree.slug}/nodes?cursor=not-a-cursor",
          "/api/techtree/v1/trees/missing-tree/nodes?cursor=not-a-cursor",
          "/api/techtree/v1/nodes/not-a-uuid"
        ] do
      assert json_response(get(conn, path), 400) ==
               error_body("invalid_input", "The request input is invalid.")
    end

    assert json_response(get(conn, "/api/techtree/v1/trees/missing-tree/nodes"), 404) ==
             error_body("not_found", "The requested public record was not found.")

    assert json_response(get(conn, "/api/techtree/v1/nodes/#{Ash.UUID.generate()}"), 404) ==
             error_body("not_found", "The requested public record was not found.")
  end

  test "authorization and availability failures use honest errors without leaking details", %{
    conn: conn
  } do
    cases = [
      {:unauthorized, 401, "unauthorized", "The request is not authorized."},
      {{:sentinel, "private details"}, 503, "temporarily_unavailable",
       "The public read is temporarily unavailable."}
    ]

    for {reason, status, code, message} <- cases do
      Process.put(:techtree_read_error, reason)

      response =
        conn
        |> Plug.Conn.put_private(:techtree_read_controller_techtree, ErrorTechtree)
        |> get("/api/techtree/v1/nodes/#{Ash.UUID.generate()}")

      assert json_response(response, status) == error_body(code, message)
      refute response.resp_body =~ "sentinel"
      refute response.resp_body =~ "private details"
    end

    Process.delete(:techtree_read_error)
  end

  test "browser and API give anonymous callers the same public authorization outcomes", %{
    conn: conn
  } do
    :ok = Techtree.ensure_seed_trees(actor: %System{})
    tree = Techtree.get_tree_by_slug!("skill-training-lab")
    node = Techtree.import_public_node!(tree.id, "Parity node", nil, nil, actor: %System{})

    {:ok, tree_view, _html} = live(conn, "/techtree/#{tree.slug}")
    assert render_async(tree_view) =~ "Parity node"

    api_tree = get(conn, "/api/techtree/v1/trees/#{tree.slug}/nodes")
    assert node.id in page_ids(json_response(api_tree, 200))

    {:ok, node_view, _html} = live(conn, "/techtree/nodes/#{node.id}")
    assert render_async(node_view) =~ "Parity node"

    assert json_response(get(conn, "/api/techtree/v1/nodes/#{node.id}"), 200)["data"]["id"] ==
             node.id

    missing_id = Ash.UUID.generate()
    {:ok, missing_view, _html} = live(conn, "/techtree/nodes/#{missing_id}")
    assert render_async(missing_view) =~ "Node not found"

    assert json_response(get(conn, "/api/techtree/v1/nodes/#{missing_id}"), 404)["error"]["code"] ==
             "not_found"
  end

  defp tree!(suffix) do
    unique = Elixir.System.unique_integer([:positive])

    Techtree.upsert_seed_tree!(
      "zs63-#{suffix}-#{unique}",
      "zs6.3 #{suffix} #{unique}",
      "Public test tree.",
      1_000_000 + unique,
      actor: %System{}
    )
  end

  defp set_published_at(node, published_at) do
    Ecto.Adapters.SQL.query!(
      AshPlatform.Repo,
      "UPDATE techtree.nodes SET published_at = $1 WHERE id = $2",
      [published_at, Ecto.UUID.dump!(node.id)]
    )
  end

  defp rewrite_cursor(cursor, rewrite) do
    {:ok, json} = Base.url_decode64(cursor, padding: false)

    json
    |> Jason.decode!()
    |> rewrite.()
    |> Jason.encode!()
    |> Base.url_encode64(padding: false)
  end

  defp get_page(conn, slug, cursor, limit) do
    query = URI.encode_query(Enum.reject([limit: limit, cursor: cursor], &is_nil(elem(&1, 1))))

    conn
    |> get("/api/techtree/v1/trees/#{slug}/nodes?#{query}")
    |> json_response(200)
  end

  defp page_ids(page), do: Enum.map(page["data"], & &1["id"])

  defp error_body(code, message),
    do: %{"error" => %{"code" => code, "message" => message}}
end
