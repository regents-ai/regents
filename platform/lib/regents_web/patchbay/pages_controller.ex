defmodule RegentsWeb.Patchbay.PagesController do
  @moduledoc """
  The pages that say where to find help, who runs Patchbay, how to reach them,
  what is kept about a visitor, and how to call the service from code. A
  request for a page's Markdown is answered before the router
  (`RegentsWeb.Patchbay.PublicDocuments`); this shows the page.
  """

  use RegentsWeb, :controller

  alias Regents.Patchbay.Changelog
  alias Regents.Patchbay.Forum.Capabilities
  alias Regents.Patchbay.WrittenPages
  alias RegentsWeb.Patchbay.Layouts
  alias RegentsWeb.Patchbay.PublicDocuments

  def help(conn, _params), do: conn |> page("/patchbay/help") |> render(:help)

  def webmcp(conn, _params), do: conn |> page("/patchbay/webmcp") |> render(:webmcp)

  def about(conn, _params),
    do: conn |> page("/patchbay/about") |> render(:about, html: WrittenPages.about().html)

  def privacy(conn, _params), do: conn |> page("/patchbay/privacy") |> render(:privacy)

  def terms(conn, _params), do: conn |> page("/patchbay/terms") |> render(:terms)

  def changelog(conn, params) do
    page = changelog_page!(params)

    conn
    |> merge_assigns(changelog_head(page) ++ Layouts.frame(conn, []))
    |> render(:changelog, page: page, intro: Changelog.intro())
  end

  def docs(conn, _params) do
    conn
    |> page("/patchbay/docs")
    |> render(:docs, core_tools: Capabilities.core(), more_tools: Capabilities.more())
  end

  @doc "Every agent, each linked to its own Patchbay page, and how to pair one."
  def agents(conn, _params) do
    conn
    |> page("/patchbay/agents")
    |> render(:agents, agents: PublicDocuments.agents())
  end

  # The developer page's old address, moved for good.
  def developers(conn, _params),
    do: conn |> put_status(:moved_permanently) |> redirect(to: ~p"/patchbay/docs")

  # The changelog shows twelve entries a page, newest first. The first page is
  # /patchbay/changelog itself and each older one is `?page=N`, N written in
  # plain digits from 2; any other value names no page. The Markdown answer is
  # the whole changelog on every page.
  defp changelog_page!(params) do
    number = changelog_number!(params)

    case Changelog.page(number) do
      {:ok, entries, pages} -> %{entries: entries, number: number, pages: pages}
      :error -> raise RegentsWeb.NotFoundError
    end
  end

  defp changelog_head(%{number: 1}), do: PublicDocuments.page("/patchbay/changelog")

  defp changelog_head(%{number: number, pages: pages}),
    do: PublicDocuments.changelog_page(number, pages)

  defp changelog_number!(%{"page" => page}) when is_binary(page) do
    if Regex.match?(~r/\A[1-9][0-9]*\z/, page) and page != "1",
      do: String.to_integer(page),
      else: raise(RegentsWeb.NotFoundError)
  end

  defp changelog_number!(%{"page" => _not_plain_digits}), do: raise(RegentsWeb.NotFoundError)
  defp changelog_number!(_first_page), do: 1

  defp page(conn, path),
    do: merge_assigns(conn, PublicDocuments.page(path) ++ Layouts.frame(conn, []))
end
