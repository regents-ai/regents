defmodule RegentsWeb.ProductCapabilitiesController do
  @moduledoc """
  Serves the canonical per-product capabilities manifest at
  `GET /api/v1/<product>/capabilities`, backed directly by each product's
  committed `priv/<product>/tool_manifest.json` so WebMCP (`product_webmcp.ts`),
  Hosted MCP, CLI docs, and external agents all read one source of truth.
  """

  use RegentsWeb, :controller

  alias Regents.SiteTools

  def show(conn, _params) do
    product = conn.private.product

    case SiteTools.manifest(product) do
      {:ok, manifest} ->
        origin = RegentsWeb.Endpoint.url()

        body =
          manifest
          |> Map.put("product", product)
          |> Map.put("audience", "regents")
          |> Map.put("origin", origin)
          |> Map.put("mcp_endpoint", "#{origin}/mcp")
          |> Map.put("cli_prefix", "regents #{product}")
          |> Map.put("docs", %{
            "llms" => "#{origin}/#{product}/llms.txt",
            "skill" => "#{origin}/#{product}/skill.md",
            "agents" => "#{origin}/#{product}/agents.md",
            "docs" => "#{origin}/docs/#{product}",
            "cli" => "#{origin}/docs/cli"
          })
          |> Map.put("build", Application.fetch_env!(:regents, :build))
          |> Jason.encode!()

        send_cached_json(conn, body)

      {:error, _reason} ->
        conn
        |> put_status(404)
        |> json(%{
          error: %{
            code: "product_capabilities_unavailable",
            message: "Capabilities manifest is unavailable for this product.",
            hint: "Check GET /api/v1/site-tools or GET /capabilities.json."
          }
        })
    end
  end

  defp send_cached_json(conn, body) do
    etag = ~s("#{Base.encode16(:crypto.hash(:sha256, body), case: :lower)}")

    conn =
      conn
      |> put_resp_header("access-control-allow-origin", "*")
      |> put_resp_header("cache-control", "public, max-age=300")
      |> put_resp_header("etag", etag)

    if etag in get_req_header(conn, "if-none-match") do
      send_resp(conn, 304, "")
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, body)
    end
  end
end
