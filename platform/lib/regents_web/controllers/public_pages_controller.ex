defmodule RegentsWeb.PublicPagesController do
  @moduledoc "Public documentation and discovery; no account or database reads."
  use RegentsWeb, :controller
  alias RegentsWeb.PublicDocuments

  def show(conn, _params) do
    document = PublicDocuments.document(conn.request_path) || raise(RegentsWeb.NotFoundError)
    render(conn, :show, [document: document] ++ PublicDocuments.page(conn.request_path))
  end

  def developers(conn, _params), do: conn |> put_status(301) |> redirect(to: "/docs")
  def openapi(conn, _params), do: json(conn, PublicDocuments.openapi())

  def llms(conn, _params), do: send_cached(conn, "text/plain", PublicDocuments.llms())

  def capabilities(conn, _params), do: json(conn, PublicDocuments.capabilities())

  def agents(conn, _params), do: send_cached(conn, "text/markdown", PublicDocuments.agents())

  def skill(conn, _params), do: send_cached(conn, "text/markdown", PublicDocuments.skill())

  def robots(conn, _params) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(
      200,
      "User-agent: *\nAllow: /\n\nSitemap: #{PublicDocuments.url("/sitemap.xml")}\n"
    )
  end

  def security(conn, _params),
    do:
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(200, PublicDocuments.security_txt())

  # XML from fixed page paths; PublicDocuments.sitemap/0 escapes every location.
  # sobelow_skip ["XSS.SendResp"]
  def sitemap(conn, _params),
    do:
      conn
      |> put_resp_content_type("application/xml")
      |> send_resp(200, PublicDocuments.sitemap())

  # These documents change only with a release: a sha256 ETag of the body and a
  # five-minute public cache, as the template sends on its agent files. Every
  # type and body comes from this site's own documents, never from the request.
  # sobelow_skip ["XSS.ContentType", "XSS.SendResp"]
  defp send_cached(conn, type, body) do
    conn
    |> put_resp_header("etag", ~s("#{Base.encode16(:crypto.hash(:sha256, body), case: :lower)}"))
    |> put_resp_header("cache-control", "public, max-age=300")
    |> put_resp_content_type(type)
    |> send_resp(200, body)
  end
end

defmodule RegentsWeb.PublicPagesHTML do
  @moduledoc false
  use RegentsWeb, :html

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
        {RegentsWeb.PublicDocuments.html(@document.markdown)}
      </main>
    </div>
    """
  end
end
