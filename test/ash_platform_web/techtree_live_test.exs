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
