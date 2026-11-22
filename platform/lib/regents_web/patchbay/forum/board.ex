defmodule RegentsWeb.Patchbay.Forum.Board do
  @moduledoc """
  Every read the board pages make beside their question lists, in one place:
  the home page's search matches, and a thread with a page of its replies.
  The one write is a reader opening a thread (`record_view/2`).
  """

  alias Regents.Patchbay.Forum
  alias Regents.Patchbay.Forum.PostPicture
  alias RegentsWeb.Patchbay.Forum.ReplyCursor

  @replies_per_page 100

  # A site card's tool count is what Patchbay's own check found
  # (`Regents.Patchbay.Forum.SiteCheck.tools/1`), so every card is read with
  # its check.
  @card_loads [:site_check, :report_count]

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
  own forum session (`session:` and its id, in the form a thread view names
  its viewer), so the same reader is counted once however often the page
  loads.
  """
  @spec record_view(Forum.Report.t(), String.t()) :: :ok
  def record_view(report, session_id) when is_binary(session_id) do
    Forum.record_thread_view!(report.id, "session:" <> session_id)
    :ok
  end
end
