defmodule RegentsWeb.Patchbay.Forum.BoardController do
  @moduledoc """
  Patchbay's board pages: the home page with its question lists, a thread
  with its replies, agent setup, payments and each agent program's
  troubleshooting page. The pages read the stored threads and committed
  files; the one write is a reader opening a thread (`post/2`).
  """

  use RegentsWeb, :controller

  require Logger

  alias Regents.Patchbay.DatabaseBusy
  alias Regents.Patchbay.Forum.BoardActivity
  alias Regents.Patchbay.Forum.PostAddress
  alias Regents.Patchbay.Forum.PostSummary
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

  @doc """
  One post and a page of its replies: the opening page, or the page a
  continuation from this board names.

  The post answers at its own address only (`PostAddress.path/1`). Any other
  address with its id, such as `/patchbay/posts/<id>`,
  `/patchbay/reports/<id>` or one whose words are not its headline's, moves
  there for good, query and all. An id that names no post, or one held out
  of sight, is not on the board.
  """
  def post(conn, %{"id" => id} = params) do
    report = fetch_report!(id)
    path = PostAddress.path(report)

    if conn.request_path == path do
      conn
      |> viewed(report)
      |> show_report(report, params)
    else
      conn
      |> put_status(:moved_permanently)
      |> redirect(to: path <> query_part(conn.query_string))
    end
  end

  defp fetch_report!(id) do
    case Board.fetch_report(id) do
      {:ok, report} -> report
      :error -> raise RegentsWeb.NotFoundError
      {:error, failure} -> raise failure
    end
  end

  # The browser's forum identifier, kept in the signed session cookie. A
  # caller never names it, so nobody can be counted as someone else.
  @forum_session "patchbay_forum_session_id"

  # The page shows the post as read above, so a reader's first view is counted
  # from their next one. The reader is the browser's own forum session, given
  # it here when it has none. Where the site only reads, nothing is written.
  defp viewed(conn, report) do
    if Regents.read_only?() do
      conn
    else
      conn = forum_session(conn)
      :ok = Board.record_view(report, get_session(conn, @forum_session))
      conn
    end
  end

  defp forum_session(conn) do
    case get_session(conn, @forum_session) do
      id when is_binary(id) -> conn
      _none -> put_session(conn, @forum_session, Ash.UUID.generate())
    end
  end

  defp query_part(""), do: ""
  defp query_part(query), do: "?" <> query

  # A bad continuation and a reply read that fails are each said for what
  # they are, never shown as an empty thread.
  defp show_report(conn, report, params) do
    filter = if params["replies"] in ["solution", "official"], do: params["replies"], else: "all"

    case Board.thread_page(report, params["after"], filter) do
      {:ok, thread} ->
        conn
        |> merge_assigns(Layouts.frame(conn, [BoardHTML.thread_data(report, thread.replies)]))
        |> render(
          :report,
          Map.merge(thread, %{
            page_title: PostSummary.title(report),
            page_description: PostSummary.description(report),
            canonical: RegentsWeb.Endpoint.url() <> PostAddress.path(report),
            report: report,
            # The live thread under the post takes the page it was drawn with
            # (`RegentsWeb.Patchbay.ThreadLive`).
            thread: thread
          })
        )

      {:error, :invalid_cursor} ->
        conn
        |> put_status(:bad_request)
        |> page(:replies_unavailable)
        |> render(:report_error, report: report, problem: :invalid_cursor, cursor: nil)

      {:error, failure} ->
        Logger.warning("Report replies unavailable: " <> inspect(error_type(failure)))

        conn
        |> put_status(:service_unavailable)
        |> page(:replies_unavailable)
        |> render(:report_error, report: report, problem: :unavailable, cursor: params["after"])
    end
  end

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
