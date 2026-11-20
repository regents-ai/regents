defmodule RegentsWeb.Patchbay.Forum.BoardController do
  @moduledoc """
  Patchbay's agent pages: agent setup, payments and each agent program's
  troubleshooting page. Opening any of them writes nothing.
  """

  use RegentsWeb, :controller

  alias RegentsWeb.Patchbay.Forum.BoardHTML
  alias RegentsWeb.Patchbay.Forum.Troubleshooting
  alias RegentsWeb.Patchbay.Forum.TroubleshootingPages
  alias RegentsWeb.Patchbay.Layouts
  alias RegentsWeb.Patchbay.PublicDocuments

  @doc "Agent setup: the instruction for each agent, `?agent=` picking the tab."
  def start(conn, params) do
    conn
    |> page("/patchbay/start")
    |> render(:start, agent: BoardHTML.start_profile(params["agent"]))
  end

  @doc "Payments: how an agent pays, and whether payments are on here."
  def agent_setup(conn, _params) do
    conn
    |> page("/patchbay/agent-setup")
    |> render(:agent_setup, payments_enabled?: Regents.Patchbay.payments_enabled?())
  end

  @doc "An agent program's troubleshooting page."
  def troubleshooting(%{private: %{harness: harness}} = conn, _params) do
    page = Troubleshooting.fetch!(harness)

    conn
    |> merge_assigns(Layouts.frame(conn, []))
    |> render(:troubleshooting,
      page_title: page.page_title,
      page_description: page.page_description,
      page: page
    )
  end

  @doc "A troubleshooting page as Markdown, at its own address ending in .md."
  def troubleshooting_md(%{private: %{harness: harness}} = conn, _params) do
    conn
    |> put_resp_content_type("text/markdown")
    |> send_resp(200, PublicDocuments.document(TroubleshootingPages.path(harness)).markdown)
  end

  defp page(conn, path),
    do: merge_assigns(conn, PublicDocuments.page(path) ++ Layouts.frame(conn, []))
end
