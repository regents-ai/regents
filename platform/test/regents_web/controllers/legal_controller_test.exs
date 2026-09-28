defmodule RegentsWeb.LegalControllerTest do
  use RegentsWeb.ConnCase, async: true

  test "PRIVACY: the policy is on /privacy and does not carry draft placeholders" do
    conn = get(build_conn(), "/privacy")
    body = html_response(conn, 200)

    assert body =~ "Regents Labs Privacy Policy"
    assert body =~ "privacy@regents.sh"
    assert body =~ "mailto:privacy@regents.sh"
    refute body =~ "INSERT"
    refute body =~ "billing-readiness"
  end

  test "TERMS: the terms are on /terms and do not carry draft placeholders" do
    conn = get(build_conn(), "/terms")
    body = html_response(conn, 200)

    assert body =~ "Regents Labs Terms of Use"
    assert body =~ "legal@regents.sh"
    assert body =~ "mailto:legal@regents.sh"
    refute body =~ "INSERT"
  end

  test "until a theme is chosen the device decides; the homepage is always dark" do
    for path <- ["/privacy", "/"] do
      document = build_conn() |> get(path) |> html_response(200) |> LazyHTML.from_document()
      html = LazyHTML.query(document, "html")
      theme_colors = LazyHTML.query(document, "meta[name=theme-color]")

      if path == "/" do
        assert LazyHTML.attribute(html, "data-theme") == ["dark"]
        assert LazyHTML.attribute(theme_colors, "content") == ["#161616"]
      else
        assert LazyHTML.attribute(html, "data-theme") == []

        assert document
               |> LazyHTML.query("meta[name=color-scheme]")
               |> LazyHTML.attribute("content") == ["dark light"]

        assert Enum.zip(
                 LazyHTML.attribute(theme_colors, "media"),
                 LazyHTML.attribute(theme_colors, "content")
               ) == [
                 {"(prefers-color-scheme: light)", "#e5e3d2"},
                 {"(prefers-color-scheme: dark)", "#161616"}
               ]
      end
    end
  end

  test "legal and home first renders honor the saved theme" do
    for theme <- ["light", "dark"], path <- ["/privacy", "/"] do
      document =
        build_conn()
        |> put_req_cookie("regent_theme", theme)
        |> get(path)
        |> html_response(200)
        |> LazyHTML.from_document()

      expected = if path == "/", do: "dark", else: theme

      assert document |> LazyHTML.query("html") |> LazyHTML.attribute("data-brand") == [
               "platform"
             ]

      assert document |> LazyHTML.query("html") |> LazyHTML.attribute("data-theme") == [expected]

      assert document
             |> LazyHTML.query("meta[name=color-scheme]")
             |> LazyHTML.attribute("content") == [expected]
    end
  end
end
