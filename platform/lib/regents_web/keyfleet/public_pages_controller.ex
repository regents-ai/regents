defmodule RegentsWeb.Keyfleet.PublicPagesController do
  @moduledoc """
  Keyfleet's public discovery and contract endpoints: `/keyfleet/llms.txt`,
  `/keyfleet/agents.md`, `/keyfleet/help`, `/keyfleet/capabilities.json`,
  `/keyfleet/openapi.json`, `/keyfleet/api-contract.openapiv3.yaml`, and legacy
  `/keyfleet/mcp` / `/keyfleet/oauth/*` cutover redirects; no account or
  database reads.
  """
  use RegentsWeb, :controller

  alias Regents.Keyfleet.Capabilities
  alias RegentsWeb.Keyfleet.PublicDocuments

  def llms(conn, _params) do
    body = PublicDocuments.llms()
    conn |> cached(body) |> put_resp_content_type("text/plain") |> send_resp(200, body)
  end

  def agents(conn, _params) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_content_type("text/markdown")
    |> send_resp(200, PublicDocuments.agents())
  end

  def help(conn, _params) do
    body = PublicDocuments.help()
    conn |> cached(body) |> put_resp_content_type("text/markdown") |> send_resp(200, body)
  end

  def capabilities(conn, _params) do
    body =
      Capabilities.manifest()
      |> Map.put("build", Application.fetch_env!(:regents, :build))
      |> Map.put("versions", Capabilities.versions())
      |> Jason.encode!()

    conn |> cached(body) |> put_resp_content_type("application/json") |> send_resp(200, body)
  end

  def openapi(conn, _params) do
    body = Jason.encode!(PublicDocuments.openapi())
    conn |> cached(body) |> put_resp_content_type("application/json") |> send_resp(200, body)
  end

  # Static YAML contract committed in priv/keyfleet/public; Sobelow cannot verify
  # non-HTML content types on send_resp.
  # sobelow_skip ["XSS.SendResp"]
  def api_contract(conn, _params) do
    body = PublicDocuments.api_contract()
    conn |> cached(body) |> put_resp_content_type("application/yaml") |> send_resp(200, body)
  end

  @doc "Permanent redirect for legacy `keyfleet.ai/mcp` cutover requests."
  def redirect_mcp(conn, _params) do
    conn
    |> put_status(308)
    |> redirect(to: ~p"/mcp")
  end

  @doc "Permanent redirect for legacy `keyfleet.ai/oauth/*` cutover requests."
  def redirect_oauth(conn, %{"rest" => segments}) when is_list(segments) do
    target =
      case segments do
        ["register"] -> ~p"/oauth/register"
        ["token"] -> ~p"/oauth/token"
        ["revoke"] -> ~p"/oauth/revoke"
        ["authorize"] -> ~p"/oauth/authorize"
        ["connections"] -> ~p"/oauth/connections"
        ["connections", "revoke"] -> ~p"/oauth/connections/revoke"
        _other -> ~p"/oauth/authorize"
      end

    conn
    |> put_status(308)
    |> redirect(to: target)
  end

  # These documents change only with a release: a sha256 ETag of the body and a
  # five-minute public cache, as `RegentsWeb.Keyfleet.AgentFilesController` sends.
  defp cached(conn, body) do
    conn
    |> put_resp_header("etag", ~s("#{Base.encode16(:crypto.hash(:sha256, body), case: :lower)}"))
    |> put_resp_header("cache-control", "public, max-age=300")
    |> put_resp_header("access-control-allow-origin", "*")
  end
end
