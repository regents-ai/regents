defmodule AshPlatformWeb.TechtreeLiveTest do
  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatform.{Accounts, Techtree}
  alias AshPlatform.Actors.System

  @trees [
    {"GeneBench-Pro Reference Lab", "/techtree/genebench-pro-reference-lab"},
    {"Question Forge Metaskills", "/techtree/question-forge-metaskills"},
    {"New Question Candidates", "/techtree/new-question-candidates"},
    {"BixBench Capsule Lab", "/techtree/bixbench-capsule-lab"},
    {"Skill Training Lab", "/techtree/skill-training-lab"}
  ]

  test "overview explains human and agent participation and links exactly five roots", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, "/techtree")
    html = render_async(view)

    assert html =~ "Research with Techtree"
    assert html =~ "regents techtree start"
    assert html =~ "regents techtree node create"
    assert html =~ "Humans browse, run notebooks, comment, and react."

    assert Enum.map(@trees, fn {label, path} ->
             assert has_element?(view, ~s(#techtree-overview a[href="#{path}"]), label)
             label
           end) == Enum.map(@trees, &elem(&1, 0))

    refute html =~ "paid payload"
    refute has_element?(view, "#techtree-overview", "Publish")
  end

  test "tree route contains interchangeable Map and List presentations without fake nodes", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, "/techtree/bixbench-capsule-lab")
    html = render_async(view)

    assert has_element?(view, ~s(#techtree-tree[data-tree-slug="bixbench-capsule-lab"]))
    assert html =~ "BixBench Capsule Lab"
    assert html =~ "BBH training corpus"
    assert has_element?(view, ~s(a.techtree-list-tab[data-tree-presentation="list"]), "List")
    assert has_element?(view, ~s(a.techtree-map-tab[data-tree-presentation="map"]), "Map")
    assert html =~ "No nodes yet"
    refute has_element?(view, "[data-techtree-map-world]")
    refute has_element?(view, "[data-techtree-map-edges]")
    refute has_element?(view, ".techtree-map-nodes")
    refute has_element?(view, "#techtree-tree a", "Publish")
    refute has_element?(view, "#techtree-tree button", "Publish")
  end

  test "node detail is read-only for node creation and exposes local notebook and comments", %{
    conn: conn
  } do
    tree = Techtree.get_tree_by_slug!("bixbench-capsule-lab")

    node =
      Techtree.import_public_node!(
        tree.id,
        "BBH reference 001",
        "A reproducible reference node.",
        "sha256:abc123",
        actor: %System{}
      )

    {:ok, view, _html} = live(conn, "/techtree/nodes/#{node.id}")
    html = render_async(view)

    assert has_element?(view, ~s(#techtree-node[data-motion-surface="detail"]))
    assert html =~ "BBH reference 001"
    assert html =~ "A reproducible reference node."
    assert html =~ "sha256:abc123"
    assert html =~ "does not include a browser-run notebook"
    assert has_element?(view, "#comment-ledger", "Comments")
    assert html =~ "Sign in to add a comment."
    refute has_element?(view, "#techtree-node a", "Publish")
    refute has_element?(view, "#techtree-node button", "Publish")
    refute html =~ "paid payload"
  end

  test "node detail runs a verified notebook only inside an opaque credentialless sandbox", %{
    conn: conn
  } do
    tree = Techtree.get_tree_by_slug!("bixbench-capsule-lab")

    node =
      Techtree.import_public_node!(
        tree.id,
        "Interactive local evidence",
        "A small browser-run analysis.",
        "sha256:node-payload",
        actor: %System{}
      )

    source_hash = sha256("3 * 2")
    manifest_json = valid_notebook_manifest(source_hash)
    payload_hash = sha256(manifest_json)
    run_url = "http://127.0.0.1:4003/#{hash_hex(payload_hash)}/index.html"

    Techtree.import_notebook_artifact!(
      node.id,
      node.payload_hash,
      source_hash,
      payload_hash,
      "0.23.14",
      run_url,
      manifest_json,
      [
        "https://cdn.jsdelivr.net",
        "https://wasm.marimo.app",
        "https://files.pythonhosted.org"
      ],
      actor: %System{}
    )

    {:ok, view, _html} = live(conn, "/techtree/nodes/#{node.id}")
    html = render_async(view)

    assert has_element?(
             view,
             ~s(#local-notebook iframe[sandbox="allow-scripts allow-same-origin"][credentialless])
           )

    assert html =~ "Runs on this device"
    assert html =~ ~s(src="#{run_url}")
    refute has_element?(view, "#techtree-node marimo-island")
    refute html =~ "No Marimo notebook is attached"
  end

  test "tree Map and List both link persisted nodes to the same canonical detail route", %{
    conn: conn
  } do
    tree = Techtree.get_tree_by_slug!("skill-training-lab")

    node =
      Techtree.import_public_node!(tree.id, "Skill receipt", "Measured skill evidence.", nil,
        actor: %System{}
      )

    {:ok, view, _html} = live(conn, "/techtree/skill-training-lab")
    render_async(view)

    assert has_element?(
             view,
             ~s([data-techtree-map] a[href="/techtree/nodes/#{node.id}"]),
             "Skill receipt"
           )

    assert has_element?(
             view,
             ~s([data-techtree-list-panel] a[href="/techtree/nodes/#{node.id}"]),
             "Skill receipt"
           )

    assert has_element?(
             view,
             ~s([data-techtree-list-panel] li[data-motion-surface="list-item"])
           )
  end

  test "tree Map server-renders positioned variants and both edge kinds", %{conn: conn} do
    tree = Techtree.get_tree_by_slug!("question-forge-metaskills")

    first =
      Techtree.import_public_node!(tree.id, "Featured question", "A positioned node.", nil,
        actor: %System{}
      )

    second =
      Techtree.import_public_node!(tree.id, "Standard question", "Another positioned node.", nil,
        actor: %System{}
      )

    first =
      Techtree.update_node_layout!(first, 120.0, 80.0, "featured", actor: %System{})

    second =
      Techtree.update_node_layout!(second, 520.0, 240.0, "standard", actor: %System{})

    prerequisite = Techtree.create_edge!(first.id, second.id, actor: %System{})

    related =
      Techtree.create_edge!(
        second.id,
        first.id,
        %{kind: :related},
        actor: %System{}
      )

    {:ok, view, initial_html} = live(conn, "/techtree/question-forge-metaskills")

    assert initial_html =~ "data-techtree-map-world"
    assert initial_html =~ "data-techtree-map-edges"
    assert initial_html =~ ~s(data-node-id="#{first.id}")
    assert initial_html =~ ~s(data-edge-kind="prerequisite")
    assert initial_html =~ ~s(data-edge-kind="related")

    assert has_element?(
             view,
             ~s(#techtree-map-stage.techtree-map-stage[phx-hook="TechtreeCamera"][tabindex="0"][aria-label="Question Forge Metaskills node map"])
           )

    assert has_element?(
             view,
             ~s([data-techtree-map-world][data-world-width="832"][data-world-height="424"])
           )

    assert has_element?(
             view,
             ~s(li[data-node-id="#{first.id}"][data-position-source="authored"][data-display-kind="featured"][data-node-x="120.0"][data-node-y="80.0"]),
             "Featured"
           )

    assert has_element?(
             view,
             ~s(li[data-node-id="#{second.id}"][data-position-source="authored"][data-display-kind="standard"][data-node-x="520.0"][data-node-y="240.0"])
           )

    assert has_element?(
             view,
             ~s(svg[data-techtree-map-edges] > path.techtree-map-edge--prerequisite[data-from-node-id="#{prerequisite.from_node_id}"][data-to-node-id="#{prerequisite.to_node_id}"][d="M 240.0 136.0 L 640.0 296.0"])
           )

    assert has_element?(
             view,
             ~s(svg[data-techtree-map-edges] > path.techtree-map-edge--related[data-from-node-id="#{related.from_node_id}"][data-to-node-id="#{related.to_node_id}"][d="M 640.0 296.0 L 240.0 136.0"])
           )

    assert has_element?(
             view,
             ~s(.techtree-map-nodes > li[data-node-id="#{first.id}"] > a[href="/techtree/nodes/#{first.id}"])
           )
  end

  test "nodes without positions use the deterministic fallback grid", %{conn: conn} do
    tree = Techtree.get_tree_by_slug!("new-question-candidates")

    for title <- ["Fallback one", "Fallback two", "Fallback three", "Fallback four"] do
      Techtree.import_public_node!(tree.id, title, nil, nil, actor: %System{})
    end

    ordered_nodes = Techtree.list_tree_nodes!(tree.id)

    {:ok, view, initial_html} = live(conn, "/techtree/new-question-candidates")

    assert initial_html =~ "data-position-source=\"fallback\""

    for {node, {x, y}} <-
          Enum.zip(ordered_nodes, [{72, 72}, {376, 72}, {680, 72}, {72, 248}]) do
      assert has_element?(
               view,
               ~s(li[data-node-id="#{node.id}"][data-position-source="fallback"][data-node-x="#{x}"][data-node-y="#{y}"])
             )
    end

    assert has_element?(
             view,
             ~s([data-techtree-map-world][data-world-width="992"][data-world-height="432"])
           )
  end

  test "map styles disable motion and transparency effects for user preferences" do
    css = File.read!(Path.expand("../../assets/css/pages/techtree.css", __DIR__))

    assert css =~ "@media (prefers-reduced-motion: reduce)"
    assert css =~ ".techtree-list-panel,\n  .techtree-map-nodes a {\n    transition: none;"
    assert css =~ "@media (prefers-reduced-transparency: reduce)"
    assert css =~ ".techtree-map-node[data-display-kind=\"featured\"] a {\n    background:"
  end

  test "unknown node id is honest", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/techtree/nodes/#{Ash.UUID.generate()}")
    assert render_async(view) =~ "Node not found"
    assert has_element?(view, ~s(#techtree-node[data-motion-surface="detail"]))
  end

  defp valid_notebook_manifest(source_hash) do
    Jason.encode!(%{
      "schema_version" => 1,
      "runtime" => "pyodide",
      "marimo_version" => "0.23.14",
      "source_hash" => source_hash,
      "files" => [%{"path" => "index.html", "sha256" => sha256("index bytes")}]
    })
  end

  defp hash_hex("sha256:" <> hex), do: hex

  defp sha256(value) do
    "sha256:" <> (:crypto.hash(:sha256, value) |> Base.encode16(case: :lower))
  end

  test "signed humans post and remove node comments while another open view updates", %{
    conn: conn
  } do
    tree = Techtree.get_tree_by_slug!("skill-training-lab")

    node =
      Techtree.import_public_node!(tree.id, "Commented node", "Public evidence.", nil,
        actor: %System{}
      )

    account =
      Accounts.register_verified!(
        "did:privy:techtree-comment-#{Elixir.System.unique_integer([:positive])}",
        "0x1111111111111111111111111111111111111111",
        ["0x1111111111111111111111111111111111111111"],
        actor: %System{}
      )

    {:ok, public_view, _html} = live(build_conn(), "/techtree/nodes/#{node.id}")
    render_async(public_view)
    assert has_element?(public_view, "#comment-ledger", "Sign in to add a comment")
    refute has_element?(public_view, "#comment-form")

    signed_conn = init_test_session(conn, %{human_account_id: account.id})
    {:ok, signed_view, _html} = live(signed_conn, "/techtree/nodes/#{node.id}")
    render_async(signed_view)

    assert has_element?(signed_view, "#comment-form")

    signed_view
    |> form("#comment-form", comment: %{body: "# Unsupported heading"})
    |> render_submit()

    assert has_element?(signed_view, "#comment-ledger-status", "could not be posted")
    assert has_element?(signed_view, "#comment-body", "# Unsupported heading")

    signed_view
    |> form("#comment-form", comment: %{body: "Useful **evidence**"})
    |> render_submit()

    assert has_element?(signed_view, "#comment-ledger article", "Useful evidence")
    assert has_element?(public_view, "#comment-ledger article", "Useful evidence")
    assert has_element?(public_view, "#comment-ledger article", "0x1111…1111")
    refute render(public_view) =~ account.privy_user_id
    refute render(public_view) =~ "0x1111111111111111111111111111111111111111"
    assert has_element?(signed_view, "#comment-ledger button", "Delete")
    refute has_element?(public_view, "#comment-ledger button", "Delete")

    assert has_element?(
             signed_view,
             ~s(#comment-ledger button[data-reaction-value="useful"][aria-pressed="false"]),
             "Useful 0"
           )

    signed_view
    |> element(~s(#comment-ledger button[data-reaction-value="useful"]))
    |> render_click()

    assert has_element?(
             signed_view,
             ~s(#comment-ledger button[data-reaction-value="useful"][aria-pressed="true"]),
             "Useful 1"
           )

    assert has_element?(
             public_view,
             ~s(#comment-ledger [data-reaction-value="useful"]),
             "Useful 1"
           )

    signed_view
    |> element(~s(#comment-ledger button[data-reaction-value="negative"]))
    |> render_click()

    assert has_element?(
             signed_view,
             ~s(#comment-ledger button[data-reaction-value="negative"][aria-pressed="true"]),
             "Negative 1"
           )

    assert has_element?(
             public_view,
             ~s(#comment-ledger [data-reaction-value="useful"]),
             "Useful 0"
           )

    signed_view
    |> element(~s(#comment-ledger button[data-reaction-value="negative"]))
    |> render_click()

    assert has_element?(
             public_view,
             ~s(#comment-ledger [data-reaction-value="negative"]),
             "Negative 0"
           )

    signed_view
    |> element("#comment-ledger button", "Delete")
    |> render_click()

    refute has_element?(signed_view, "#comment-ledger article", "Useful evidence")
    refute has_element?(public_view, "#comment-ledger article", "Useful evidence")
  end
end
