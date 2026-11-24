defmodule RegentsWeb.ProductCapabilitiesController do
  @moduledoc """
  Serves the canonical per-product capabilities manifest at
  `GET /api/v1/<product>/capabilities`, backed directly by each product's
  committed `priv/<product>/tool_manifest.json` so WebMCP (`product_webmcp.ts`),
  Hosted MCP, CLI docs, and external agents all read one source of truth.
  """

  use RegentsWeb, :controller

  alias Regents.SiteTools
  alias RegentsWeb.PublicResponse

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
    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> PublicResponse.send_cached("application/json", body, nil)
  end
end
