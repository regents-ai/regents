defmodule RegentsWeb.PublicPagesController do
  @moduledoc "Public documentation and discovery; no account or database reads."
  use RegentsWeb, :controller
  import RegentsWeb.PublicResponse, only: [send_cached: 3, send_cached: 4]
  alias RegentsWeb.{AgentGuides, Docs, PublicDocuments}

  def show(conn, _params) do
    case PublicDocuments.document(conn.request_path) do
      nil ->
        raise RegentsWeb.NotFoundError

      document ->
        render(conn, :show, [document: document] ++ PublicDocuments.page(conn.request_path))
    end
  end

  @doc "A public page as JSON, `{title, markdown}`."
  def document(conn, _params) do
    %{title: title, markdown: markdown} = PublicDocuments.document(conn.assigns.document)
    json(conn, %{title: title, markdown: markdown})
  end

  def developers(conn, _params), do: conn |> put_status(301) |> redirect(to: "/docs")
  def openapi(conn, _params), do: json(conn, PublicDocuments.openapi())

  def llms(conn, _params), do: send_cached(conn, "text/plain", PublicDocuments.llms())

  def capabilities(conn, _params), do: json(conn, PublicDocuments.capabilities())

  def agents(conn, _params), do: send_cached(conn, "text/markdown", PublicDocuments.agents())

  def skill(conn, _params), do: send_cached(conn, "text/markdown", PublicDocuments.skill())

  def pricing(conn, _params) do
    conn
    |> put_public_cors()
    |> put_resp_header("content-disposition", ~s(inline; filename="pricing.md"))
    |> send_cached("text/markdown", PublicDocuments.pricing())
  end

  def docs_search(conn, _params) do
    send_cached(conn, "application/json", Docs.search_index(), nil)
  end

  def docs_markdown(conn, _params) do
    path =
      case conn.assigns[:docs_key] do
        key when is_binary(key) -> "/docs/" <> key
        _ -> "/docs"
      end

    case Docs.Pages.page(path) do
      nil ->
        raise RegentsWeb.NotFoundError

      page ->
        conn
        |> put_public_cors()
        |> send_cached("text/markdown", Docs.markdown(page))
    end
  end

  @doc "One agent's skill: the agent guide with that agent's Set up section added."
  def agent_skill(conn, %{"agent" => slug}) do
    case AgentGuides.skill(slug) do
      nil -> raise RegentsWeb.NotFoundError
      skill -> send_cached(conn, "text/markdown", skill)
    end
  end

  def robots(conn, _params) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, PublicDocuments.robots_txt())
  end

  def security(conn, _params),
    do:
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(200, PublicDocuments.security_txt())

  # The body is JSON built from this site's own addresses, sent as a linkset with
  # the RFC 9727 profile and RFC 8288 discovery Link headers.
  def api_catalog(conn, _params) do
    type = ~s(application/linkset+json; profile="https://www.rfc-editor.org/info/rfc9727")

    link =
      Enum.join(
        [
          ~s(<#{PublicDocuments.url("/.well-known/api-catalog")}>; rel="api-catalog"),
          ~s(<#{PublicDocuments.url("/api/v1")}>; rel="item"),
          ~s(<#{PublicDocuments.url("/openapi.json")}>; rel="service-desc"; type="application/vnd.oai.openapi+json")
        ],
        ", "
      )

    conn
    |> put_public_cors()
    |> put_resp_header("link", link)
    |> send_cached(type, Jason.encode!(PublicDocuments.api_catalog()), nil)
  end

  def ai_catalog(conn, _params) do
    conn
    |> put_public_cors(mcp: true)
    |> send_cached(
      "application/ai-catalog+json",
      Jason.encode!(PublicDocuments.ai_catalog())
    )
  end

  def mcp_server_card(conn, _params) do
    conn
    |> put_public_cors(mcp: true)
    |> send_cached(
      "application/mcp-server-card+json",
      Jason.encode!(PublicDocuments.mcp_server_card())
    )
  end

  def server_registry(conn, _params) do
    conn
    |> put_public_cors(mcp: true)
    |> send_cached("application/json", Jason.encode!(PublicDocuments.mcp_server_registry()))
  end

  def agent_skills_index(conn, _params) do
    conn
    |> put_public_cors()
    |> send_cached("application/json", Jason.encode!(PublicDocuments.agent_skills_index()))
  end

  def agent_skills_regents(conn, _params) do
    conn
    |> put_public_cors()
    |> send_cached("text/markdown", PublicDocuments.skill())
  end

  defp put_public_cors(conn, opts \\ []) do
    conn =
      conn
      |> put_resp_header("access-control-allow-origin", "*")
      |> put_resp_header("access-control-allow-methods", "GET, HEAD, OPTIONS")

    if Keyword.get(opts, :mcp, false) do
      conn
      |> put_resp_header(
        "access-control-allow-headers",
        "Accept, Content-Type, If-None-Match, MCP-Protocol-Version"
      )
      |> put_resp_header("access-control-expose-headers", "ETag")
    else
      conn
    end
  end

  # XML from fixed page paths; PublicDocuments.sitemap/0 escapes every location.
  # sobelow_skip ["XSS.SendResp"]
  def sitemap(conn, _params),
    do:
      conn
      |> put_resp_content_type("application/xml")
      |> send_resp(200, PublicDocuments.sitemap())
end

defmodule RegentsWeb.PublicPagesHTML do
  @moduledoc false
  use RegentsWeb, :html

  alias RegentsWeb.Components.{AgentMessage, Shell}

  # The bar holds the theme switch only: these pages read no account.
  def show(assigns) do
    ~H"""
    <Regent.Site.bar id="site-bar" product="regents">
      <:account><Shell.theme_toggle id="theme-control" /></:account>
    </Regent.Site.bar>
    <div class="rl-root legal-root rg-sheet rg-frame public-document">
      <header class="legal-header">
        <nav class="legal-nav" aria-label="Information">
          <a
            :for={
              {label, path} <- [{"Docs", "/docs"}, {"About", "/about"}, {"Changelog", "/changelog"}]
            }
            href={path}
            aria-current={if(@conn.request_path == path, do: "page")}
          >
            {label}
          </a>
        </nav>
      </header>
      <main class="legal-page">
        {RegentsWeb.PublicDocuments.html(@document.markdown)}
        <AgentMessage.button
          :if={@conn.request_path == "/agents"}
          id="agents-message-button"
          dialog="agents-message"
        />
      </main>
    </div>
    <%!-- Outside the document, so its reading styles stay off the dialog. --%>
    <AgentMessage.dialog
      :if={@conn.request_path == "/agents"}
      id="agents-message"
      topic="agents"
      conn={@conn}
    />
    """
  end
end
