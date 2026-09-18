defmodule AshPlatformWeb.PublicPagesController do
  @moduledoc "Public documentation and discovery; no account or database reads."
  use AshPlatformWeb, :controller
  alias AshPlatformWeb.PublicDocuments

  def show(conn, _params) do
    document = PublicDocuments.document(conn.request_path)
    render(conn, :show, page_title: document.title, document: document)
  end

  def developers(conn, _params), do: conn |> put_status(301) |> redirect(to: "/docs")
  def openapi(conn, _params), do: json(conn, PublicDocuments.openapi())

  def llms(conn, _params),
    do: conn |> put_resp_content_type("text/plain") |> send_resp(200, PublicDocuments.llms())

  def robots(conn, _params) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(
      200,
      "User-agent: *\nAllow: /\n\nSitemap: #{PublicDocuments.url("/sitemap.xml")}\n"
    )
  end

  def sitemap(conn, _params),
    do:
      conn
      |> put_resp_content_type("application/xml")
      |> send_resp(200, PublicDocuments.sitemap())
end

defmodule AshPlatformWeb.PublicPagesHTML do
  @moduledoc false
  use AshPlatformWeb, :html

  def show(assigns) do
    ~H"""
    <div class="rl-root legal-root rg-sheet rg-frame public-document">
      <header class="legal-header">
        <a href={~p"/"} class="legal-home">Regents Labs</a>
        <nav class="legal-nav" aria-label="Information">
          <a
            :for={{label, path} <- [{"Docs", "/docs"}, {"About", "/about"}, {"Contact", "/contact"}]}
            href={path}
            aria-current={if(@conn.request_path == path, do: "page")}
          >
            {label}
          </a>
        </nav>
      </header>
      <main class="legal-page">
        {AshPlatformWeb.PublicDocuments.html(@document.markdown)}
      </main>
    </div>
    """
  end
end
