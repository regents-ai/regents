defmodule RegentsWeb.DocsTest do
  use RegentsWeb.ConnCase, async: true

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
    assert build_conn() |> get("/docs/nothing-here") |> response(404)

    for path <- ["/docs//pairing", "/%64ocs/pairing", "/docs/pairin%67"] do
      document = build_conn() |> get(path) |> html_response(200) |> Floki.parse_document!()

      assert [_] = Floki.find(document, ~s(.docs-nav a[aria-current=page][href="/docs/pairing"])),
             path
    end
  end
end
