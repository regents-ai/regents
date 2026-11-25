defmodule RegentsWeb.Techtree.PublicPagesController do
  @moduledoc """
  About, the agents' pages under `/techtree/agents` and Security's sample report,
  committed Markdown documents, as pages in Techtree's frame. Their header shows
  the account the session pipeline found, as the live pages' does
  (`RegentsWeb.Live.Session`). Also the Techtree skill at `/techtree/skill.md`
  and each agent's own skill at `/techtree/agents/SLUG/skill.md`
  (`RegentsWeb.Techtree.AgentGuides`). None of them reads the database for a
  visitor who is signed out.
  """

  use RegentsWeb, :controller

  alias RegentsWeb.Live.Session
  alias RegentsWeb.Techtree.AgentGuides
  alias RegentsWeb.Techtree.Layouts
  alias RegentsWeb.Techtree.PublicPagesHTML

  def show(conn, _params) do
    page = PublicPagesHTML.page(conn.request_path)

    render(conn, template(conn.request_path),
      page: page,
      page_title: page.title,
      page_description: Layouts.description(conn.request_path),
      current_path: conn.request_path,
      account_control: Session.account_control_for(conn.assigns[:current_human_account])
    )
  end

  defp template("/techtree/about"), do: :about
  defp template("/techtree/agents" <> _rest), do: :agent
  defp template(_path), do: :show

  @doc "The Techtree skill at `/techtree/skill.md`."
  def skill_guide(conn, _params), do: send_markdown(conn, AgentGuides.skill_guide())

  @doc "One agent's skill: the Techtree skill with that agent's Set up section added."
  def agent_skill_guide(conn, %{"agent" => slug}) do
    case AgentGuides.skill(slug) do
      nil -> raise RegentsWeb.NotFoundError
      skill -> send_markdown(conn, skill)
    end
  end

  @doc "Permanent redirect for legacy `techtree.sh/oauth/*` cutover requests."
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

  defp send_markdown(conn, body) do
    conn
    |> put_resp_header("etag", ~s("#{Base.encode16(:crypto.hash(:sha256, body), case: :lower)}"))
    |> put_resp_header("cache-control", "public, max-age=300")
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_content_type("text/markdown", "utf-8")
    |> send_resp(200, body)
  end
end
