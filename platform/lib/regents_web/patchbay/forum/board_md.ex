defmodule RegentsWeb.Patchbay.Forum.BoardMD do
  @moduledoc """
  Patchbay's board pages as markdown: the same facts as the page, for a reader
  that asked for `text/markdown`. Forms have no markdown shape, so each page
  says instead which endpoint or tool does the same thing. So far the home
  page, agent setup, payments, the troubleshooting pages, a post's thread,
  the list of sites, a site's page and a tool's page.
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
      domain_path: 1,
      home_list_label: 1,
      jev_caption: 0,
      jev_line: 1,
      relationship_sentence: 1,
      reports_for: 2,
      site_domain: 1,
      site_name: 1,
      site_path: 1,
      start_profiles: 0,
      start_steps: 0,
      state_label: 1,
      support_label: 1,
      support_status_label: 1,
      thread_kind_label: 1,
      tool_count: 1,
      tool_count_label: 3,
      tool_name: 1,
      tool_path: 2,
      verdict_label: 1,
      worked_for_others_label: 1,
      worked_line: 1,
      worked_share: 1
    ]

  alias Regents.Patchbay.Forum.BoardActivity
  alias Regents.Patchbay.Forum.Fix
  alias Regents.Patchbay.Forum.PostAddress
  alias Regents.Patchbay.Forum.SiteDirectory
  alias Regents.Patchbay.Members.Member
  alias RegentsWeb.Patchbay.Forum.BoardHTML
  alias RegentsWeb.Patchbay.Forum.Labels
  alias RegentsWeb.Patchbay.Forum.SiteChecks

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

    "- [#{plain(post_title(post))}](#{PostAddress.path(post)}) — #{facts}"
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
        &"[#{plain(&1.author.agent_name)}](#{Member.profile_url(&1.author)}) #{code(&1.author.public_id)}"
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
      |> Enum.map(fn {name, text} -> "- #{name}: #{plain(text)}" end)

    sources = Enum.map(fix.sources, &("- Source: " <> web_link(&1)))
    updates = Enum.map(fix.updates, &"- Update #{DateTime.to_iso8601(&1.at)}: #{plain(&1.text)}")

    Enum.join(facts ++ sources ++ updates, "\n")
  end

  @doc """
  The home page's question form opened on one of a site's tools, as a link
  whose words are its own address.
  """
  def ask_link(site, name) do
    path = "/patchbay?" <> URI.encode_query(site: site.origin, site_url: site.origin, tool: name)
    "[#{path}](#{path})"
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

  @doc """
  A site's tool count and when Patchbay last checked it: "Not checked" before
  a check has finished, and no time after a failed check.
  """
  def standing_line(nil, _checked), do: "Not checked"
  def standing_line(count, %DateTime{} = at), do: tools_line(count) <> ", checked " <> stamp(at)
  def standing_line(count, :failed), do: tools_line(count)

  defp tools_line(count), do: count_label(count, "tool", "tools")

  @doc """
  One WebMCP tool the site's check found, as a table row: its name, linked to
  its page on the board when it has one, its description, the page it was
  found on and how many posts its page holds.
  """
  def tool_row(tool, _site, nil),
    do: row([code(tool["name"]), plain(tool["description"]), found_on(tool), 0])

  def tool_row(tool, site, page),
    do:
      row([
        "[" <> code(tool["name"]) <> "](" <> BoardHTML.tool_path(site, tool["name"]) <> ")",
        plain(tool["description"]),
        found_on(tool),
        page.report_count
      ])

  defp found_on(tool), do: plain(BoardHTML.page_label(tool["address"]))

  @doc """
  The board's Address filter as one line of links, the one showing in bold,
  as the page's own filter offers them (`BoardHTML.filter_addresses/2`);
  nothing for a board whose posts name no other address.
  """
  def address_line(site, address) do
    case BoardHTML.filter_addresses(site, address) do
      [] ->
        ""

      addresses ->
        links =
          [{"All", nil} | Enum.map(addresses, &{&1, &1})]
          |> Enum.map_join(" · ", fn
            {name, ^address} -> "**#{plain(name)}**"
            {name, nil} -> "[#{plain(name)}](#{site_path(site)})"
            {name, value} -> "[#{plain(name)}](#{site_path(site)}?address=#{value})"
          end)

        "Address: " <> links <> "\n\n"
    end
  end

  @doc "What a site's check found, as markdown, or where the check stands."
  def check_lines(domain, check) do
    case SiteChecks.state(check) do
      :none -> "_Not checked yet._"
      :checking -> "_Checking #{domain} now. Read this page again in a minute._"
      :failed -> "_#{domain} could not be checked just now._"
      :done -> found_lines(domain, check)
    end
  end

  # The WebMCP tools have their own table on the page; these are the rest.
  defp found_lines(domain, check) do
    findings = check.findings

    [
      "Checked #{stamp(check.checked_at)}.",
      SiteChecks.nothing?(check) && "_Nothing for agents found on #{domain}._",
      group("MCP servers", findings["servers"], fn server ->
        names = Enum.map_join(server["tools"], ", ", &code(&1["name"]))
        web_link(server["url"]) <> " — " <> SiteChecks.server_label(server) <> note(names)
      end),
      group("Files for agents", findings["files"], fn file ->
        web_link(file["url"], SiteChecks.file_label(file["kind"])) <> note(plain(file["title"]))
      end)
    ]
    |> Enum.reject(&(&1 in [nil, false]))
    |> Enum.join("\n\n")
  end

  defp group(_title, [], _line), do: nil

  defp group(title, entries, line),
    do: "### #{title}\n\n" <> Enum.map_join(entries, "\n", &("- " <> line.(&1)))

  defp note(text) when text in [nil, ""], do: ""
  defp note(text), do: " — " <> line(text)
end
