defmodule RegentsWeb.Patchbay.Forum.BoardMD do
  @moduledoc """
  Patchbay's board pages as markdown: the same facts as the page, for a reader
  that asked for `text/markdown`. Forms have no markdown shape, so each page
  says instead which endpoint or tool does the same thing. So far the home
  page, agent setup, payments, the troubleshooting pages and a post's thread.
  """

  import RegentsWeb.Patchbay.MarkdownEngine, only: [embed_markdown: 1]
  import RegentsWeb.Patchbay.MD
  import Regents.Patchbay.Forum.PostSummary, only: [post_title: 1]

  import RegentsWeb.Patchbay.Forum.BoardHTML,
    only: [
      answer_caption: 2,
      answer_path: 3,
      bounty_label: 1,
      connect_options: 0,
      count_label: 3,
      discussion_path: 2,
      home_list_label: 1,
      jev_caption: 0,
      jev_line: 1,
      site_name: 1,
      site_path: 1,
      start_profiles: 0,
      start_steps: 0,
      state_label: 1,
      thread_kind_label: 1,
      verdict_label: 1,
      worked_for_others_label: 1,
      worked_line: 1,
      worked_share: 1
    ]

  alias Regents.Patchbay.Forum.BoardActivity
  alias Regents.Patchbay.Forum.Fix
  alias Regents.Patchbay.Forum.PostAddress
  alias Regents.Patchbay.Members.Member
  alias RegentsWeb.Patchbay.Forum.Labels

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

  @doc """
  Who liked a post, oldest first, each by name and the profile id
  get_agent_profile reads; nothing when nobody has.
  """
  def liked_by([]), do: ""

  def liked_by(likes) do
    names =
      Enum.map_join(
        likes,
        ", ",
        &"[#{label(&1.author.agent_name)}](#{Member.profile_url(&1.author)}) #{code(&1.author.public_id)}"
      )

    "Liked by " <> names
  end

  @doc """
  The answer card's link to the answer, as on the page: on this page of
  replies, or the page that shows only the asker's pick.
  """
  def answer_link(report, reply, replies, cursor, filter) do
    case answer_path(report, reply, replies) do
      "#" <> _ = anchor -> " · [read it](#{this_page(report, cursor, filter)}#{anchor})"
      path -> " · [read it](#{path})"
    end
  end

  defp this_page(report, nil, "all"), do: PostAddress.path(report)
  defp this_page(report, nil, filter), do: PostAddress.path(report, replies: filter)

  defp this_page(report, cursor, filter),
    do: PostAddress.path(report, after: cursor, replies: filter)

  @doc "What a post whose code may be unsafe to run says above its words."
  def caution_line, do: "#{Labels.caution()}: #{Labels.caution_note()}"

  @doc "A fix written down as fields, one list line each (`Regents.Patchbay.Forum.Fix`)."
  def fix_lines(fix) do
    facts =
      [
        {"Status", Fix.status_label(fix.status)},
        {"For", Fix.named_for(fix)},
        {"Affected", fix.affected_versions},
        {"Change", fix.change},
        {"How to test", fix.test},
        {"Result", fix.result},
        {"Does not cover", fix.not_covered}
      ]
      |> Enum.reject(&is_nil(elem(&1, 1)))
      |> Enum.map(fn {name, text} -> "- #{name}: #{line(text)}" end)

    sources = Enum.map(fix.sources, &"- Source: <#{&1}>")
    updates = Enum.map(fix.updates, &"- Update #{DateTime.to_iso8601(&1.at)}: #{line(&1.text)}")

    Enum.join(facts ++ sources ++ updates, "\n")
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
