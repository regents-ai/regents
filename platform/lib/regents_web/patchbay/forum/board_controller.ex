defmodule RegentsWeb.Patchbay.Forum.BoardController do
  @moduledoc """
  Patchbay's board pages: the home page with its question lists, agent setup,
  payments and each agent program's troubleshooting page. Opening any of them
  writes nothing: the pages read the stored threads and committed files only.
  """

  use RegentsWeb, :controller

  require Logger

  alias Regents.Patchbay.DatabaseBusy
  alias Regents.Patchbay.Forum.BoardActivity
  alias Regents.Patchbay.Forum.SearchUnavailable
  alias Regents.Patchbay.Incidents
  alias RegentsWeb.Patchbay.BusyPage
  alias RegentsWeb.Patchbay.Forum.Board
  alias RegentsWeb.Patchbay.Forum.BoardHTML
  alias RegentsWeb.Patchbay.Forum.BoardMD
  alias RegentsWeb.Patchbay.Forum.Discussions
  alias RegentsWeb.Patchbay.Forum.Troubleshooting
  alias RegentsWeb.Patchbay.Forum.TroubleshootingPages
  alias RegentsWeb.Patchbay.Layouts
  alias RegentsWeb.Patchbay.PublicDocuments

  plug :put_view, html: BoardHTML, md: BoardMD

  # A read the database is too busy to answer asks to be opened again shortly.
  # Any other error goes on exactly as raised, so Phoenix still answers a
  # request no action clause matches with 400.
  def action(conn, options) do
    super(conn, options)
  catch
    :error, reason ->
      case DatabaseBusy.kind(reason) do
        nil -> :erlang.raise(:error, reason, __STACKTRACE__)
        kind -> BusyPage.respond(conn, kind)
      end
  end

  @doc """
  The home page: the questions, narrowed by the tabs, a search, a site, a tool
  or a tag. A list narrowed to a site Patchbay has no record of is refused.
  """
  def home(conn, params) do
    case Discussions.filters(params) do
      {:ok, filters} -> render_questions(conn, params, filters)
      {:error, :unknown_site} -> unknown_site(conn)
    end
  end

  defp unknown_site(conn) do
    conn
    |> put_status(:unprocessable_entity)
    |> page(:unknown_site)
    |> render(:unknown_site)
  end

  # The questions. A list that could not be read says so where it would have
  # been; the navigation still shows. Only the questions are the page itself,
  # so only their failure is a 503, and that includes failing to read whether
  # a named site is on record. A search the site is too busy for says so
  # instead, and asks to be sent again shortly.
  defp render_questions(conn, params, filters) do
    case discussions(filters, params["after"]) do
      {:error, :invalid_cursor} ->
        conn
        |> put_flash(:error, "That discussion page does not match these filters.")
        |> redirect(to: BoardHTML.discussion_path(filters))

      {:error, :unknown_site} ->
        unknown_site(conn)

      {reports, next_page} ->
        matches = searched(Board.matches(filters.q), "Search matches")
        found_nothing? = filters.q != "" and reports == [] and matches == %{sites: [], tools: []}

        conn
        |> listed(reports)
        |> page(:home)
        |> render(:home,
          filters: filters,
          reports: reports,
          next_page: next_page,
          current_page: params["after"],
          matches: matches,
          post_count: post_count(filters),
          activity: section(BoardActivity.reading(), "Board figures"),
          found_nothing: found_nothing?,
          ask_open: found_nothing? or ask_open?(params),
          incidents: Incidents.active()
        )
    end
  end

  # How many threads the list holds across its pages, beside its heading. A
  # list with words in it is a search and is not counted: its count would read
  # the search a second time.
  defp post_count(%{q: q}) when q != "", do: nil
  defp post_count(filters), do: section(Discussions.count(filters), "Question count")

  # The form under Ask a question opens when a link asks for it, or names what
  # to fill it with: the site, a tool, what to ask about or tags. Signed out,
  # it opens on its sign-in prompt.
  defp ask_open?(params) do
    params["ask"] == "1" or is_binary(params["tool"]) or
      Enum.any?(~w(goal site_url topic_tags), &filled?(params[&1]))
  end

  defp filled?(value), do: is_binary(value) and String.trim(value) != ""

  defp discussions(filters, after_token) do
    case Discussions.page(filters, after_token) do
      {:ok, reports, next_page} -> {reports, next_page}
      {:error, refused} when refused in [:invalid_cursor, :unknown_site] -> {:error, refused}
      {:error, failure} -> {searched({:error, failure}, "Discussions"), nil}
    end
  end

  # A search the site or its database is too busy for says so in its place,
  # apart from a read that failed for any other reason.
  defp searched({:ok, value}, _name), do: value

  defp searched({:error, failure}, name) do
    if SearchUnavailable.in?(failure) or DatabaseBusy.kind(failure) != nil,
      do: :busy,
      else: section({:error, failure}, name)
  end

  # Only the questions are the page itself. A busy search asks to be sent
  # again shortly.
  defp listed(conn, :busy) do
    conn
    |> put_status(:service_unavailable)
    |> put_resp_header("retry-after", DatabaseBusy.retry_after())
  end

  defp listed(conn, :unavailable), do: put_status(conn, :service_unavailable)
  defp listed(conn, _reports), do: put_status(conn, :ok)

  defp section({:ok, value}, _name), do: value

  defp section({:error, failure}, name) do
    Logger.warning(
      name <> " could not be read" <> read_of(failure) <> ": " <> inspect(error_type(failure))
    )

    :unavailable
  end

  # Which read failed, by its resource and action only: never what it was
  # asked for. Ash names the query on the error it returns.
  defp read_of(%{query: %Ash.Query{resource: resource, action: %{name: action}}}),
    do: " (#{inspect(resource)}.#{action})"

  defp read_of(_failure), do: ""

  defp error_type(failure) when is_struct(failure), do: failure.__struct__
  defp error_type(failure), do: failure

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

  defp page(conn, key),
    do: merge_assigns(conn, PublicDocuments.page(key) ++ Layouts.frame(conn, []))
end
