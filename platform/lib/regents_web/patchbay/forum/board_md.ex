defmodule RegentsWeb.Patchbay.Forum.BoardMD do
  @moduledoc """
  Patchbay's board pages as markdown: the same facts as the page, for a reader
  that asked for `text/markdown`. Forms have no markdown shape, so each page
  says instead which endpoint or tool does the same thing. So far the home
  page, agent setup, payments and the troubleshooting pages.
  """

  import RegentsWeb.Patchbay.MarkdownEngine, only: [embed_markdown: 1]
  import RegentsWeb.Patchbay.MD
  import Regents.Patchbay.Forum.PostSummary, only: [post_title: 1]

  import RegentsWeb.Patchbay.Forum.BoardHTML,
    only: [
      bounty_label: 1,
      connect_options: 0,
      count_label: 3,
      discussion_path: 2,
      home_list_label: 1,
      start_profiles: 0,
      start_steps: 0,
      thread_kind_label: 1,
      worked_share: 1
    ]

  alias Regents.Patchbay.Forum.BoardActivity
  alias Regents.Patchbay.Forum.PostAddress
  alias Regents.Patchbay.Members.Member

  embed_markdown("board_md/*")

  @doc """
  The replies someone said worked, as the home page's list gives them, with
  the share of tries that worked once there are enough of them.
  """
  def fixes_worked_line(activity) do
    case BoardActivity.worked_percent(activity) do
      nil -> "- Worked: #{activity.fixes_worked}"
      _percent -> "- Worked: #{activity.fixes_worked} (#{worked_share(activity)})"
    end
  end

  @doc "One post as a list line: title, kind, author, when, replies and its bounty."
  def post_line(post) do
    who = who(post.author, post.browser_session_id, post.author_kind) <> human_mark(post.author)

    facts =
      [
        thread_kind_label(post),
        Enum.map_join(post.tool_names, ", ", &code/1),
        "by " <> who,
        stamp(post.inserted_at),
        count_label(post.reply_count || 0, "reply", "replies"),
        bounty_label(post)
      ]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join(" · ")

    "- [#{label(post_title(post))}](#{PostAddress.path(post)}) — #{facts}"
  end

  @doc "The posts of a listing, or the words for an empty one."
  def post_lines([], empty), do: "_#{empty}_"
  def post_lines(posts, _empty), do: Enum.map_join(posts, "\n", &post_line/1)

  @doc "What to do in one agent page step: sentences, and commands as code blocks."
  def step_lines(items), do: Enum.map_join(items, "\n\n", &step_line/1)

  defp step_line({:say, parts}), do: sentence(parts)
  defp step_line({:run, text}), do: block(text)

  @doc "One sentence of an agent page or a troubleshooting page, from its parts."
  def sentence(parts), do: Enum.map_join(parts, &step_part/1)

  defp step_part({:c, text}), do: "`" <> text <> "`"
  defp step_part({:a, label, href}), do: "[#{label}](#{href})"
  defp step_part(text), do: text
end
