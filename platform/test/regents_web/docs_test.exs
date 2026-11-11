defmodule RegentsWeb.DocsTest do
  use RegentsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias RegentsWeb.Docs.Pages
  alias RegentsWeb.PublicDocuments

  test "every docs page answers as a page and as Markdown, and its links to other docs pages lead somewhere" do
    docs = PublicDocuments.url("/docs")

    for path <- Pages.paths() do
      document = build_conn() |> get(path) |> html_response(200) |> Floki.parse_document!()
      assert [_] = Floki.find(document, ~s(.docs-nav a[aria-current=page][href="#{path}"])), path

      for href <- Floki.attribute(document, ".docs-prose a", "href"),
          String.starts_with?(href, docs) do
        linked =
          href |> String.replace_prefix(PublicDocuments.url(""), "") |> String.split("#") |> hd()

        assert linked in Pages.paths(), "#{path} links to #{href}"
      end

      markdown = build_conn() |> put_req_header("accept", "text/markdown") |> get(path)
      assert response(markdown, 200) =~ ~r/\A# /, path
    end
  end

  test "a docs address with no page is not found, and a docs address spelled oddly still opens its page" do
    assert_error_sent 404, fn -> get(build_conn(), "/docs/nothing-here") end

    for path <- ["/docs//pairing", "/%64ocs/pairing", "/docs/pairin%67"] do
      document = build_conn() |> get(path) |> html_response(200) |> Floki.parse_document!()

      assert [_] = Floki.find(document, ~s(.docs-nav a[aria-current=page][href="/docs/pairing"])),
             path
    end
  end

  test "About and every docs page open inside the site with its sidebar", %{conn: conn} do
    for path <- ["/about", "/docs", "/docs/limits"] do
      {:ok, view, _html} = live(conn, path)

      assert has_element?(view, "#app-shell #shell-sidebar"), path
      assert has_element?(view, "#route-content h1"), path
    end

    {:ok, view, _html} = live(conn, "/docs/limits")
    assert has_element?(view, ~s(#shell-sidebar a[aria-current=page][href="/docs"]), "Docs")
    assert has_element?(view, ~s(.docs-nav a[aria-current=page][href="/docs/limits"]))
    assert has_element?(view, "#route-content h1.docs-title", "Limits")

    {:ok, view, _html} = live(conn, "/about")
    assert has_element?(view, ~s(#shell-sidebar a[aria-current=page][href="/about"]))
  end

  test "a docs page moves to the next one inside the site", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/docs")

    assert {:error, {:live_redirect, %{to: "/docs/limits"}}} =
             view |> element(".docs-pager__next") |> render_click()
  end

  test "a docs address with no page does not open", %{conn: conn} do
    assert_raise RegentsWeb.NotFoundError, fn -> live(conn, "/docs/not-a-page") end
  end
end
