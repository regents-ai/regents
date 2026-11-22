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

  alias Regents.Account.AccessContext
  alias Regents.Account.Actors.Human
  alias Regents.Account.Formation
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
      account_control: account_control(conn.assigns.current_human_account)
    )
  end

  defp template("/techtree/about"), do: :about
  defp template("/techtree/agents" <> _rest), do: :agent
  defp template(_path), do: :show

  @doc "The Techtree skill at `/techtree/skill.md`."
  def skill_guide(conn, _params), do: send_cached(conn, AgentGuides.skill_guide())

  @doc "One agent's skill: the Techtree skill with that agent's Set up section added."
  def agent_skill_guide(conn, %{"agent" => slug}) do
    case AgentGuides.skill(slug) do
      nil -> raise RegentsWeb.NotFoundError
      skill -> send_cached(conn, skill)
    end
  end

  # These change only with a release: a sha256 entity tag of the body and a
  # five-minute public cache, as techtree.sh sends them.
  defp send_cached(conn, body) do
    conn
    |> put_resp_header("etag", ~s("#{Base.encode16(:crypto.hash(:sha256, body), case: :lower)}"))
    |> put_resp_header("cache-control", "public, max-age=300")
    |> put_resp_content_type("text/markdown", "utf-8")
    |> send_resp(200, body)
  end

  defp account_control(nil), do: AccessContext.account_control(AccessContext.anonymous())

  defp account_control(account) do
    regent =
      case Formation.get_my_regent(actor: Human.for_account(account)) do
        {:ok, regent} -> regent
        _no_regent -> nil
      end

    AccessContext.account_control(AccessContext.human(account), regent)
  end
end
