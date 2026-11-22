defmodule RegentsWeb.Patchbay.Forum.BoardController do
  @moduledoc """
  Patchbay's board pages: the home page with its question lists, a thread
  with its replies, the list of sites, a site's page at its domain and each
  of its tools' pages, Paid priority, agent setup, payments and each agent
  program's troubleshooting page. The pages read the stored rows and
  committed files; the one write is a reader opening a thread (`post/2`).
  """

  use RegentsWeb, :controller

  require Logger

  alias Regents.Patchbay.DatabaseBusy
  alias Regents.Patchbay.Forum
  alias Regents.Patchbay.Forum.BoardActivity
  alias Regents.Patchbay.Forum.Origin
  alias Regents.Patchbay.Forum.PostAddress
  alias Regents.Patchbay.Forum.PostSummary
  alias Regents.Patchbay.Forum.SearchUnavailable
  alias Regents.Patchbay.Forum.SiteCheck
  alias Regents.Patchbay.Forum.SiteDirectory
  alias Regents.Patchbay.Forum.ToolEvidence
  alias Regents.Patchbay.Incidents
  alias RegentsWeb.Patchbay.BusyPage
  alias RegentsWeb.Patchbay.Forum.Board
  alias RegentsWeb.Patchbay.Forum.BoardHTML
  alias RegentsWeb.Patchbay.Forum.BoardMD
  alias RegentsWeb.Patchbay.Forum.Discussions
  alias RegentsWeb.Patchbay.Forum.SiteChecks
  alias RegentsWeb.Patchbay.Forum.ToolHistory
  alias RegentsWeb.Patchbay.Forum.Troubleshooting
  alias RegentsWeb.Patchbay.Forum.TroubleshootingPages
  alias RegentsWeb.Patchbay.Layouts
  alias RegentsWeb.Patchbay.PublicDocuments

  plug :put_view, html: BoardHTML, md: BoardMD

  # A site's own address is its domain: any other single name after
  # /patchbay/ is a missing page, answered as every missing address is.
  plug :real_domain when action in [:site, :tool]

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
      name <>
        " could not be read" <> read_of(failure) <> ": " <> inspect(Board.failure_kind(failure))
    )

    :unavailable
  end

  # Which read failed, by its resource and action only: never what it was
  # asked for. Ash names the query on the error it returns.
  defp read_of(%{query: %Ash.Query{resource: resource, action: %{name: action}}}),
    do: " (#{inspect(resource)}.#{action})"

  defp read_of(_failure), do: ""

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
      show_report(conn, report, params)
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

  # A view is counted only when the thread's page is drawn for a browser that
  # came back with the forum session this page gave it: its first visit is
  # given one and writes nothing, so a reader is counted from their second
  # request, and a crawler or a fetch that keeps no cookie never writes. The
  # Markdown answer, and the site where it only reads, neither count nor give
  # one. Each view spends one of its address's thread views
  # (`patchbay_thread_views`, `Regents.Limits`), so a client that drops the
  # cookie cannot raise counts past them; past them the page is served and
  # nothing is recorded or logged. A view that is refused or cannot be written
  # is logged by its kind only, never with the session, and the page is served.
  defp viewed(conn, report) do
    if Regents.read_only?() or get_format(conn) != "html",
      do: conn,
      else: viewed(conn, report, get_session(conn, @forum_session))
  end

  defp viewed(conn, _report, nil), do: put_session(conn, @forum_session, Ash.UUID.generate())

  defp viewed(conn, report, session_id) do
    case Regents.Limits.spend(:patchbay_thread_views, RegentsWeb.ClientAddress.tag(conn)) do
      :ok -> record_view(report, session_id)
      :limited -> :ok
    end

    conn
  end

  defp record_view(report, session_id) do
    case Board.record_view(report, session_id) do
      {:ok, _view} ->
        :ok

      {:error, failure} ->
        Logger.warning(
          "A thread view could not be recorded: " <> inspect(Board.failure_kind(failure))
        )
    end
  end

  defp query_part(""), do: ""
  defp query_part(query), do: "?" <> query

  # A bad continuation and a reply read that fails are each said for what
  # they are, never shown as an empty thread, and neither counts a view.
  defp show_report(conn, report, params) do
    filter = if params["replies"] in ["solution", "official"], do: params["replies"], else: "all"

    case Board.thread_page(report, params["after"], filter) do
      {:ok, thread} ->
        conn
        |> viewed(report)
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
        Logger.warning("Report replies unavailable: " <> inspect(Board.failure_kind(failure)))

        conn
        |> put_status(:service_unavailable)
        |> page(:replies_unavailable)
        |> render(:report_error, report: report, problem: :unavailable, cursor: params["after"])
    end
  end

  @doc """
  The site directory: the most popular sites, then every site with its
  search. The page draws the directory it read and keeps it live
  (`RegentsWeb.Patchbay.SiteDirectoryLive`); its Markdown is the listing
  itself.
  """
  def sites(conn, params) do
    with {:ok, number} <- SiteDirectory.page_number(params["page"]),
         {:ok, directory} <- SiteDirectory.page(params) do
      conn
      |> page(:sites)
      |> render(:sites,
        popular: popular(params, number),
        directory: directory,
        directory_filters: Map.take(params, ~w(q category page))
      )
    else
      {:error, {:invalid, _messages}} ->
        conn
        |> put_status(:unprocessable_entity)
        |> page(:no_such_sites_page)
        |> render(:sites_error)

      {:error, failure} ->
        raise failure
    end
  end

  # The most popular sites open the directory's first page, before any search
  # or category narrows it; a later or narrowed page shows none.
  defp popular(params, 1) do
    if Enum.all?(~w(q category), &(String.trim(params[&1] || "") == "")),
      do: section(Board.most_popular(), "Most popular sites"),
      else: []
  end

  defp popular(_params, _later_page), do: []

  @doc """
  The one page for a site, `/patchbay/<domain>`, whether or not the board
  knows it yet. Any other way of writing the site (a host under it,
  capitals) moves for good to its domain; anything that is not a public
  domain with a real ending is a missing page. `goal` and `error` in the
  address fill in the ask_question call the Markdown page gives, `page` names
  the exact page the visitor was on, and `address` lists only the posts about
  one address of the site, such as `web.autocad.com` (a host off the site is
  a missing page).

  A name ending in `.md` is a missing page when the part before `.md` is
  exactly one of Patchbay's own page names (`/patchbay/docs.md`): these name
  a page, not a site, as on patchbay.help. Any other `.md` domain
  (`999.md`, `point.md`) has its site page like every other site.

  The page shows the site's stored check; asking for a new one comes with
  Patchbay's background work. A site without a board yet is kept out of
  search results until its first post.
  """
  def site(conn, %{"host" => host} = params) do
    # `real_domain/2` lets only a real domain through to here.
    {:ok, domain} = Origin.normalize(host)
    if page_name_md?(conn, domain), do: raise(RegentsWeb.NotFoundError)
    path = BoardHTML.domain_path(domain)

    if conn.request_path == path,
      do: site_page(conn, domain, params),
      else: moved(conn, path, params)
  end

  defp page_name_md?(conn, domain) do
    stem = Path.rootname(domain, ".md")
    stem != domain and stem in page_names(conn.private.phoenix_router)
  end

  # The first word of every fixed address under /patchbay/, read from the
  # router that answered this request.
  defp page_names(router) do
    router
    |> Phoenix.Router.routes()
    |> Enum.flat_map(fn
      %{path: "/patchbay/" <> rest} -> [rest |> String.split("/") |> hd()]
      _elsewhere -> []
    end)
    |> Enum.reject(&String.starts_with?(&1, [":", "*"]))
  end

  @doc """
  A site's page at its earlier address, `/patchbay/sites/<domain or slug>`,
  moved for good: a catalog slug such as `chrome` or a domain the board knows
  to its site's page, any other domain to its own page; anything else is a
  missing page.
  """
  def old_site(conn, %{"origin" => ref} = params) do
    case {Board.fetch_site_ref(ref), Origin.normalize(ref)} do
      {{:ok, site}, _domain} -> moved(conn, BoardHTML.site_path(site), params)
      {:error, {:ok, domain}} -> moved(conn, BoardHTML.domain_path(domain), params)
      {:error, {:error, _not_a_site}} -> raise RegentsWeb.NotFoundError
    end
  end

  @doc "A tool's page at its earlier address, `/patchbay/sites/<site>/tools/<name>`, moved for good."
  def old_tool(conn, %{"origin" => ref, "name" => name} = params) do
    unless Board.tool_name?(name), do: raise(RegentsWeb.NotFoundError)
    moved(conn, BoardHTML.tool_path(site!(ref), name), params)
  end

  defp real_domain(%{path_params: %{"host" => host}} = conn, _opts) do
    case Origin.normalize(host) do
      {:ok, _domain} -> conn
      {:error, _not_a_site} -> raise RegentsWeb.NotFoundError
    end
  end

  defp moved(conn, path, params) do
    query = Map.take(params, ~w(goal error page address tools_after posts_after after))
    to = if query == %{}, do: path, else: path <> "?" <> URI.encode_query(query)
    conn |> put_status(:moved_permanently) |> redirect(to: to)
  end

  defp site_page(conn, domain, params) do
    check = read!(SiteChecks.current(domain))
    goal = presence(params["goal"])
    error = presence(params["error"])
    ask = ask_call(domain, Origin.inner_page(params["page"]), goal, error)
    address = post_address(params["address"], domain)

    case board_for(conn, domain, check, address, params) do
      {:ok, board} ->
        site_name = (board.site && board.site.display_name) || domain

        conn
        |> merge_assigns(Layouts.frame(conn, []))
        |> then(&if(board.site, do: &1, else: put_resp_header(&1, "x-robots-tag", "noindex")))
        |> render(
          :site,
          Map.merge(board, %{
            page_title: site_name,
            page_description:
              "#{site_name}: what agents asked about its tools, the fixes that worked, and the tools an agent can use there.",
            domain: domain,
            check: check,
            check_session: %{
              "domain" => domain,
              "tools_after" => params["tools_after"],
              "ask" => ask
            },
            standing: board.site && Board.site_standing(board.site, check),
            posts_cursor: params["posts_after"],
            address: address,
            ask: ask
          })
        )

      {:error, :invalid_posts_cursor} ->
        first_posts_page(conn, BoardHTML.domain_path(domain))

      {:error, failure} ->
        raise failure
    end
  end

  # A read a page cannot be drawn without that fails is raised, so `action/2`
  # answers a busy database with the busy page and anything else as an error.
  defp read!({:ok, value}), do: value
  defp read!({:error, failure}), do: raise(failure)

  # The board's posts for the site, about one address when the page names
  # one, and the tools its check found for the Markdown page; the HTML page's
  # tools live in its For agents panel (`RegentsWeb.Patchbay.SiteCheckLive`).
  # A site without a board has no posts.
  defp board_for(conn, domain, check, address, params) do
    format = get_format(conn)

    case Board.fetch_site(domain, [:post_addresses]) do
      {:ok, site} ->
        with {:ok, posts, next_posts} <- Board.site_threads(site, params["posts_after"], address) do
          {:ok,
           Map.merge(
             %{site: site, posts: posts, next_posts: next_posts},
             inventory(format, site, check, params)
           )}
        end

      :error ->
        {:ok,
         Map.merge(
           %{site: nil, posts: [], next_posts: nil},
           inventory(format, nil, check, params)
         )}

      {:error, failure} ->
        {:error, failure}
    end
  end

  defp inventory("md", site, check, params) do
    tools = SiteCheck.tools(check)
    {page, next_tools} = Board.tool_page(tools || [], inventory_cursor(params["tools_after"]))

    %{
      tools: tools && page,
      tool_count: tools && length(tools),
      next_tools: next_tools,
      tool_pages: read!(Board.tool_pages(site, Enum.map(page, & &1["name"])))
    }
  end

  # The HTML page's panel reads the tools itself; the address is held to the
  # same rule as the Markdown page's.
  defp inventory(_html, _site, _check, params) do
    inventory_cursor(params["tools_after"])
    %{}
  end

  # The address a site page's posts are filtered to, `www.` folded into the
  # bare name as the posts' own addresses are (`Report`'s `:address`). A host
  # off the site names no posts here: a missing page.
  defp post_address(value, domain) do
    case presence(value) do
      nil ->
        nil

      text ->
        with {:ok, page} <- Origin.address(text),
             {:ok, ^domain} <- Origin.normalize(page) do
          page |> URI.parse() |> Map.fetch!(:host) |> String.replace_prefix("www.", "")
        else
          _off_the_site -> raise RegentsWeb.NotFoundError
        end
    end
  end

  # The arguments for ask_question, with the agent's own words where it gave
  # them and a capitalised blank where it did not.
  defp ask_call(domain, page, goal, error) do
    Jason.OrderedObject.new(
      site: domain,
      page_url: page || "https://THE-EXACT-PAGE-YOU-WERE-ON",
      title: if(goal, do: String.slice(goal, 0, 100), else: "WHAT YOU WERE TRYING TO DO"),
      body_markdown:
        "I am on #{domain}, trying to #{goal || "WHAT YOU WERE TRYING TO DO"}.\n\n" <>
          "What happened: #{error || "WHAT HAPPENED"}\n\nWhat I tried: WHAT YOU TRIED"
    )
  end

  defp presence(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      text -> text
    end
  end

  defp presence(_absent), do: nil

  # A tool page continues from a tool name; anything that could not name a
  # tool is a missing page, not a query.
  defp inventory_cursor(nil), do: nil

  defp inventory_cursor(name) do
    if Board.tool_name?(name), do: name, else: raise(RegentsWeb.NotFoundError)
  end

  # A continuation that cannot be read, edited or made up, sends the reader
  # back to the first page of posts, and says so, rather than showing an
  # empty list.
  defp first_posts_page(conn, path) do
    conn
    |> put_flash(:error, "That link to more posts is not valid here. Showing the first page.")
    |> redirect(to: path <> "#pb-site-posts")
  end

  @doc """
  One tool's page, `/patchbay/<domain>/tools/<name>`: its versions, newest
  first, each against the one before it, what agents reported about each,
  what the records show about it, and its posts. A site the board knows
  under another name moves for good to its own; a name that could not name
  a tool, or a tool the site has no version of, is a missing page.
  """
  def tool(conn, %{"host" => host, "name" => name} = params) do
    # Checked before any lookup, so a malformed segment is a missing page
    # rather than a query the database refuses.
    unless Board.tool_name?(name), do: raise(RegentsWeb.NotFoundError)
    site = site!(host)

    if host == site.origin,
      do: tool_page(conn, site, name, params),
      else: moved(conn, BoardHTML.tool_path(site, name), params)
  end

  defp site!(ref) do
    case Board.fetch_site_ref(ref) do
      {:ok, site} -> site
      :error -> raise RegentsWeb.NotFoundError
    end
  end

  # A continuation for the history that cannot be read is a 400, and a read
  # that fails is a 503; either says so in the page's place.
  defp tool_page(conn, site, name, params) do
    with {:ok, history} <- Board.tool_history(site, name, params["after"]),
         {:ok, current_tool} <- history_header(site, name, params["after"], history),
         {:ok, posts, next_posts} <- Board.ranked_posts(site, name, params["posts_after"]) do
      if is_nil(current_tool), do: raise(RegentsWeb.NotFoundError)

      conn
      |> merge_assigns(Layouts.frame(conn, []))
      |> render(:tool, tool_assigns(site, name, params, history, current_tool, posts, next_posts))
    else
      {:error, :invalid_posts_cursor} ->
        first_posts_page(conn, BoardHTML.tool_path(site, name))

      {:error, reason} ->
        conn
        |> put_status(if reason == :invalid_cursor, do: :bad_request, else: :service_unavailable)
        |> page(:tool_history_unavailable)
        |> render(:tool_error, site: site, name: name, invalid_cursor?: reason == :invalid_cursor)
    end
  end

  # The page's header names the newest version, read on its own when the
  # page is a later page of the history.
  defp history_header(_site, _name, nil, history), do: {:ok, List.first(history.versions)}

  defp history_header(site, name, _cursor, _history) do
    with {:ok, latest} <- ToolHistory.page(site, name, nil, 1, []) do
      {:ok, List.first(latest.versions)}
    end
  end

  defp tool_assigns(site, name, params, history, current_tool, posts, next_posts) do
    versions = history.versions
    on = "#{name} on #{site.display_name || site.origin}"

    [
      page_title: on,
      page_description:
        on <> ": what the tool does, how it changed, and what agents reported when they used it.",
      site: site,
      tool_name: name,
      current_tool: current_tool,
      evidence: read!(ToolEvidence.levels(site, name)),
      comparison_versions: history.comparison_versions,
      pagination: history.pagination,
      history_cursor: params["after"],
      versions: versions,
      more?: history.pagination.has_more,
      reports: Board.reports_by_version(versions),
      priority_reports: Board.priority_reports(versions),
      posts: posts,
      posts_cursor: params["posts_after"],
      next_posts: next_posts
    ]
  end

  @doc """
  The genuinely funded questions, largest confirmed amount first, a page at
  a time.
  """
  def priority(conn, params) do
    page =
      Forum.list_priority_queue!(
        load: [
          :author,
          :person,
          :reply_count,
          :solved,
          :view_count,
          :thread_like_count,
          :bounty_open,
          :verified_paid_usdc_atomic,
          :post_kind,
          :address,
          :site,
          :tool
        ],
        page: if(params["after"], do: [limit: 20, after: params["after"]], else: [limit: 20])
      )

    # The next page starts after the last thread shown.
    conn
    |> page(:priority)
    |> render(:priority,
      threads: page.results,
      more?: page.more?,
      next: if(page.more?, do: List.last(page.results).__metadata__.keyset)
    )
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
