defmodule RegentsWeb.Patchbay.Forum.Board do
  @moduledoc """
  Every read the board pages make beside their question lists, in one place:
  the home page's search matches, a thread with a page of its replies, and a
  site with its posts, its status and the tools its check found. The one
  write is a reader opening a thread (`record_view/2`).
  """

  alias Regents.Patchbay.Forum
  alias Regents.Patchbay.Forum.Feed
  alias Regents.Patchbay.Forum.PostPicture
  alias Regents.Patchbay.Forum.SiteCheck
  alias Regents.Patchbay.Forum.SiteDirectory
  alias Regents.Patchbay.Forum.ToolName
  alias RegentsWeb.Patchbay.Forum.Discussions
  alias RegentsWeb.Patchbay.Forum.ReplyCursor
  alias RegentsWeb.Patchbay.Forum.SiteChecks

  @replies_per_page 100
  @tools_per_page 20
  @ranked_posts 20

  # A site card's tool count is what Patchbay's own check found
  # (`Regents.Patchbay.Forum.SiteCheck.tools/1`), so every card is read with
  # its check. A site's own page reads its check itself, board or not.
  @card_loads [:site_check, :report_count]

  # A site's own page puts the site on its posts itself (`on_site/2`).
  @site_post_loads [
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
    :tool
  ]

  @report_loads [
    :author,
    :person,
    :reply_count,
    :solved,
    :view_count,
    :thread_like_count,
    :bounty_open,
    :post_kind,
    :site,
    :tool,
    :discussion_state,
    :jev_reading,
    :post_like_count,
    :picture_count
  ]

  @doc """
  The sites and tools whose names match what a visitor typed into the front
  page's search, for the answers shown above the matching discussions. Fewer
  than two letters matches nothing.
  """
  @spec matches(String.t()) ::
          {:ok, %{sites: [Forum.Site.t()], tools: [Forum.Tool.t()]}} | {:error, term()}
  def matches(q) do
    text = String.trim(q)

    if String.length(text) >= 2 do
      with {:ok, sites} <- Forum.find_sites(text, load: @card_loads),
           {:ok, tools} <- Forum.find_tools(text),
           do: {:ok, %{sites: sites, tools: tools}}
    else
      {:ok, %{sites: [], tools: []}}
    end
  end

  @doc """
  The most popular sites, at the top of `/patchbay/sites`: the catalog's
  featured surfaces, each read as the same site record as everywhere else.
  """
  @spec most_popular() :: {:ok, [Forum.Site.t()]} | {:error, term()}
  def most_popular do
    surfaces = SiteDirectory.featured_surfaces()
    origins = Enum.map(surfaces, & &1["origin"])

    with {:ok, %{results: sites}} <-
           Forum.list_directory(query: [filter: [origin: [in: origins]]], load: @card_loads) do
      by_origin = Map.new(sites, &{&1.origin, &1})

      {:ok,
       for surface <- surfaces,
           site = by_origin[surface["origin"]],
           site do
         site
         |> Map.put(:display_name, surface["display_name"])
         |> Map.put(:screenshot_path, surface["screenshot_path"])
       end}
    end
  end

  @doc """
  The site filed under a domain, if the board has one, with anything more a
  page shows loaded in the same read. A read that fails is raised, never
  taken for a site the board does not have.
  """
  @spec fetch_site(String.t(), list()) :: {:ok, Forum.Site.t()} | :error
  def fetch_site(origin, load \\ []) do
    case Forum.get_site_by_origin(origin, load: load) do
      {:ok, site} -> {:ok, site}
      {:error, %Ash.Error.Invalid{}} -> :error
      {:error, failure} -> raise failure
    end
  end

  @doc """
  The site a catalog slug names, such as `chrome` for the Chrome row. A read
  that fails is raised, never taken for a slug the board does not have.
  """
  @spec fetch_slug(String.t()) :: {:ok, Forum.Site.t()} | :error
  def fetch_slug(ref) do
    case Forum.get_site_by_slug(ref) do
      {:ok, site} -> {:ok, site}
      {:error, %Ash.Error.Invalid{}} -> :error
      {:error, failure} -> raise failure
    end
  end

  @doc """
  One page of the tools a site's check found (`Regents.Patchbay.Forum.SiteCheck.tools/1`),
  in name order from after `after_name`, and the name the next page
  continues from.
  """
  @spec tool_page([map()], String.t() | nil) :: {[map()], String.t() | nil}
  def tool_page(tools, after_name) do
    {page, rest} =
      tools
      |> Enum.sort_by(& &1["name"])
      |> Enum.filter(&(is_nil(after_name) or &1["name"] > after_name))
      |> Enum.split(@tools_per_page)

    {page, if(rest != [], do: List.last(page)["name"])}
  end

  @doc """
  The board's own page for each of these tool names that has one, by name,
  with how many posts it holds. The names are a page of the ones a check
  found, so the read is as small as that page.
  """
  @spec tool_pages(Forum.Site.t() | nil, [String.t()]) :: %{optional(String.t()) => map()}
  def tool_pages(nil, _names), do: %{}
  def tool_pages(_site, []), do: %{}

  def tool_pages(site, names),
    do:
      site.id
      |> Forum.list_site_tools_named!(names, load: [:report_count])
      |> Map.new(&{&1.name, &1})

  @doc "Whether an address segment could name a tool at all; anything else is not on the board."
  @spec tool_name?(term()) :: boolean()
  def tool_name?(name), do: ToolName.valid?(name)

  @doc """
  Solved and open on a site: how many tools Patchbay's check found there, nil
  before a check has finished (`Regents.Patchbay.Forum.SiteCheck.tools/1` of
  `check`), and when Patchbay last checked the site
  (`RegentsWeb.Patchbay.Forum.SiteChecks.last_checked/1`), then its solved
  and still-open questions, the newest three of each with how many there are
  in all.
  """
  @spec site_standing(Forum.Site.t(), Ash.Resource.record() | nil) :: map()
  def site_standing(site, check) do
    tools = SiteCheck.tools(check)

    %{
      tool_count: tools && length(tools),
      checked: SiteChecks.last_checked(check),
      solved: site_questions(site, "solved"),
      open: site_questions(site, "open")
    }
  end

  defp site_questions(site, scope) do
    {:ok, filters} = Discussions.filters(%{"site" => site.origin, "scope" => scope})

    page =
      Forum.list_feed_reports!(query: Feed.query(filters), page: [limit: 3, count: true])

    %{count: page.count, threads: on_site(page.results, site)}
  end

  @doc """
  One page of every published thread on a site — the questions that name no
  tool and the posts about any of its tools — open bounties first, then where
  an answer worked for the most people, and the cursor of the page after it
  when there is one. With `address`, only the threads about that address,
  such as `web.autocad.com` (`Regents.Patchbay.Forum.Report`'s `:address`).
  """
  @spec site_threads(Forum.Site.t(), String.t() | nil, String.t() | nil) ::
          {:ok, [Forum.Report.t()], String.t() | nil} | {:error, :invalid_posts_cursor}
  def site_threads(site, cursor, address) do
    site.id
    |> Forum.list_ranked_threads_for_site(address,
      load: @site_post_loads,
      page: post_page(cursor)
    )
    |> post_page_result()
    |> case do
      {:ok, posts, next} -> {:ok, on_site(posts, site), next}
      invalid -> invalid
    end
  end

  # Every post on a site's page is filed under that site, and so is any tool
  # it names, so the site the page already holds is put on each rather than
  # read again for every page.
  defp on_site(posts, site), do: Enum.map(posts, &put_site(&1, site))

  defp put_site(%Forum.Report{tool: %Forum.Tool{} = tool} = post, site),
    do: %{post | site: site, tool: %{tool | site: site}}

  defp put_site(%Forum.Report{} = post, site), do: %{post | site: site}

  @doc "How many threads one page of a site's posts holds."
  @spec ranked_page_size() :: pos_integer()
  def ranked_page_size, do: @ranked_posts

  defp post_page(nil), do: [limit: @ranked_posts]
  defp post_page(cursor), do: [limit: @ranked_posts, after: cursor]

  # A page of posts and the cursor that continues it, which never expires. A
  # cursor that cannot be read — edited or made up — is said so, never shown
  # as an empty list.
  defp post_page_result({:ok, %{results: results, more?: more?}}) do
    {:ok, results, if(more?, do: List.last(results).__metadata__.keyset)}
  end

  defp post_page_result({:error, %Ash.Error.Invalid{errors: errors}}) do
    if Enum.any?(errors, &match?(%Ash.Error.Page.InvalidKeyset{}, &1)),
      do: {:error, :invalid_posts_cursor},
      else: raise(Ash.Error.Invalid, errors: errors)
  end

  defp post_page_result({:error, failure}), do: raise(failure)

  @doc """
  One report, with its author and the tool and site it belongs to. An address
  that names no report, or one held out of sight, is `:error`; a read that
  failed is its error.
  """
  @spec fetch_report(String.t()) :: {:ok, Forum.Report.t()} | :error | {:error, term()}
  def fetch_report(id) do
    with {:ok, %{visibility: :published} = report} <-
           Forum.get_report(id, load: @report_loads),
         {:ok, report} <- Ash.load(report, parts(report), reuse_values?: true) do
      {:ok, without_parts(report)}
    else
      # An address that names no report, or names one held out of sight, is
      # not on the board.
      {:ok, _held} -> :error
      {:error, %Ash.Error.Invalid{}} -> :error
      {:error, failure} -> {:error, failure}
    end
  end

  # Its likes, pictures and picked replies are read only when it has them;
  # `without_parts/1` gives the rest their empty value.
  defp parts(report) do
    [
      post_likes: report.post_like_count > 0 && [:author],
      # The pictures' places only; each image is read when it is served.
      pictures: report.picture_count > 0 && Ash.Query.select(PostPicture, [:id, :position]),
      accepted_reply: report.accepted_reply_id && [:author],
      solution_reply: report.solution_reply_id && [:author, :worked_for_others, :last_worked_at]
    ]
    |> Enum.filter(fn {_part, load} -> load end)
  end

  defp without_parts(report) do
    Enum.reduce(
      [post_likes: [], pictures: [], accepted_reply: nil, solution_reply: nil],
      report,
      fn {part, empty}, report ->
        case Map.fetch!(report, part) do
          %Ash.NotLoaded{} -> Map.put(report, part, empty)
          _loaded -> report
        end
      end
    )
  end

  @doc """
  What a post's page shows under the post: the page of replies `cursor` and
  `filter` name, with the continuation after it, and the asker's pick. The
  page and its live thread (`RegentsWeb.Patchbay.ThreadLive`) both draw from
  it.
  """
  @spec thread_page(Forum.Report.t(), String.t() | nil, String.t()) ::
          {:ok, map()} | {:error, term()}
  def thread_page(report, cursor, filter) do
    with {:ok, keyset} <- ReplyCursor.verify(report.id, cursor),
         {:ok, replies, next_cursor} <- replies(report, keyset, filter) do
      {:ok,
       %{
         answer: report.solution_reply,
         reply_filter: filter,
         replies: replies,
         replies_cursor: cursor,
         next_cursor: next_cursor
       }}
    end
  end

  @doc "How many replies one page of a thread holds."
  @spec replies_per_page() :: pos_integer()
  def replies_per_page, do: @replies_per_page

  # One page of the replies to a report, most helpful first, in
  # `Regents.Patchbay.Forum.Reply`'s `:for_report` order: the asker's pick,
  # then by helpfulness with a tie going to the newer reply, then the
  # unmarked replies newest first. The opening page, or the one that follows
  # a continuation the board handed out, with the continuation for the page
  # after it when there is one.
  defp replies(report, keyset, filter) do
    paging =
      if keyset,
        do: [limit: @replies_per_page, after: keyset],
        else: [limit: @replies_per_page]

    query =
      case filter do
        "solution" -> [filter: [id: report.solution_reply_id]]
        "official" -> [filter: [owner_response: true]]
        _ -> []
      end

    # The count is read after the page: read with it, the page loses its order.
    with {:ok, page} <-
           Forum.list_replies_for_report(report.id,
             query: query,
             load: [:author, :person, likes: [:author]],
             page: paging
           ),
         {:ok, page} <- Ash.load(page, :worked_for_others) do
      {:ok, page.results, continuation(report, page)}
    end
  end

  defp continuation(report, %{more?: true, results: [_first | _rest] = results}),
    do: ReplyCursor.sign(report.id, List.last(results).__metadata__.keyset)

  defp continuation(_report, _page), do: nil

  @doc """
  Records that this reader opened the thread. The reader is the browser's
  own forum session, so the same reader is counted once however often the
  page loads.
  """
  @spec record_view(Forum.Report.t(), String.t()) :: :ok
  def record_view(report, session_id) when is_binary(session_id) do
    Forum.record_thread_view!(report.id, session_id)
    :ok
  end
end
