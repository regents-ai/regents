defmodule RegentsWeb.AgentGuidesTest do
  use RegentsWeb.ConnCase, async: true

  alias RegentsWeb.AgentGuides

  test "every agent the pairing box offers has a page and a skill", %{conn: conn} do
    html = conn |> get("/agents") |> html_response(200)
    assert html =~ "data-brand"

    for harness <- RegentAgents.Harness.featured() do
      path = AgentGuides.path(harness)

      assert html =~ path
      assert conn |> get(path) |> html_response(200) =~ "data-brand"

      skill = get(conn, path <> "/skill.md")
      assert String.starts_with?(response(skill, 200), RegentsWeb.PublicDocuments.skill())
      assert ["text/markdown" <> _] = get_resp_header(skill, "content-type")
    end
  end

  test "an agent nobody offers has no page and no skill", %{conn: conn} do
    assert_error_sent 404, fn -> get(conn, "/agents/nobody") end
    assert_error_sent 404, fn -> get(conn, "/agents/nobody/skill.md") end
  end

  test "the pages name only what this site has", %{conn: conn} do
    for path <- AgentGuides.paths() do
      markdown = RegentsWeb.PublicDocuments.document(path).markdown

      refute markdown =~ ~r/ash.template|\/api\/v1\/(?!account\/points)|pin a note|\{\{/i, path
      assert conn |> get(path) |> html_response(200)
    end
  end

  test "agent guides and the changelog are in the sitemap and answer as Markdown", %{conn: conn} do
    sitemap = conn |> get("/sitemap.xml") |> response(200)

    for path <- ["/changelog" | AgentGuides.paths()] do
      assert sitemap =~ "<loc>#{RegentsWeb.PublicDocuments.url(path)}</loc>"

      markdown = conn |> put_req_header("accept", "text/markdown") |> get(path)
      assert response(markdown, 200) =~ "# "
      assert ["text/markdown" <> _] = get_resp_header(markdown, "content-type")
    end
  end

  test "the changelog is the changes page's words at its own address", %{conn: conn} do
    html = conn |> get("/changelog") |> html_response(200)

    assert html =~ "data-brand"

    assert RegentsWeb.PublicDocuments.document("/changelog").markdown ==
             RegentsWeb.PublicDocuments.document("/docs/changes").markdown
  end

  test "the API catalog is a linkset with no character set", %{conn: conn} do
    catalog = get(conn, "/.well-known/api-catalog")

    assert %{"linkset" => [%{"anchor" => anchor, "service-desc" => [_], "service-doc" => [_]}]} =
             Jason.decode!(response(catalog, 200))

    assert anchor == RegentsWeb.PublicDocuments.url("/api/v1")

    assert get_resp_header(catalog, "content-type") == [
             ~s(application/linkset+json; profile="https://www.rfc-editor.org/info/rfc9727")
           ]
  end

  test "the developer documentation answers as JSON", %{conn: conn} do
    assert conn |> get("/api/v1/docs") |> json_response(200) ==
             Map.new(RegentsWeb.PublicDocuments.document("/docs"), fn {key, value} ->
               {to_string(key), value}
             end)
  end
end
