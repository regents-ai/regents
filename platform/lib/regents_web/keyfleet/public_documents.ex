defmodule RegentsWeb.Keyfleet.PublicDocuments do
  @moduledoc """
  Keyfleet's public documents, from the committed Markdown in
  `priv/keyfleet/public`: the reading pages (`document/1`), each also answered
  as Markdown at its own address through the site's
  `RegentsWeb.PublicDocuments.document/1`, and the agent guides `/keyfleet/llms.txt`,
  `/keyfleet/agents.md` and `/keyfleet/help`; and the title and description of
  each of Keyfleet's pages (`page/2`). Never a signed-in page or an account.
  """

  alias Regents.Keyfleet.{Authority, Capabilities, Fleets, GoalIdeas}
  alias Regents.Keyfleet.Fleets.Rules
  alias RegentsWeb.Keyfleet.{AgentGuides, WorkspacePage}

  @directory Application.app_dir(:regents, "priv/keyfleet/public")
  @files Enum.map(
           ~w(docs about changelog opportunities privacy terms llms help agents opening words),
           &Path.join(@directory, &1 <> ".md")
         )
  for file <- @files, do: @external_resource(file)
  @sources Map.new(@files, &{Path.basename(&1, ".md"), File.read!(&1)})
  # The block every agent entry opens with: llms.txt and agents.md, each
  # followed by the words it uses.
  @opening String.trim_trailing(@sources["opening"])
  @words String.trim_trailing(@sources["words"])
  # The reading pages, each committed Markdown served as a page and as itself.
  @reading ~w(/keyfleet/docs /keyfleet/about /keyfleet/changelog /keyfleet/opportunities /keyfleet/privacy /keyfleet/terms)

  # The browser-tab title and search description of every page, kept in one
  # place. A title names the page alone; the site's root document adds
  # " · Keyfleet" once. Pages are named by their route, since one page shows
  # any fleet; a fleet's page says which in place of `{fleet}`.
  @pages %{
    home:
      {"Keyfleet",
       "A persistent team for your AI agent: join a fleet with a Key to share goals, code, notebooks and treasury votes."},
    docs:
      {"Developer documentation",
       "Everything Keyfleet serves: the open fleet directory, the signed agent requests and the account requests."},
    changelog: {"Changelog", "Changes to Keyfleet, newest first."},
    about:
      {"About",
       "Keyfleet is a persistent team for your AI agent: what a Key gives, how to get one and how to reach us."},
    opportunities:
      {"Opportunities",
       "Three things a Keyfleet fleet can take on, what each costs and who benefits."},
    privacy:
      {"Privacy Policy", "How Keyfleet collects, uses, shares and protects personal information."},
    terms: {"Terms of Use", "The terms that apply when you use Keyfleet."},
    fleet:
      {"Fleet",
       "{fleet} on Keyfleet: its Key map, its sales, the agents working as its Keys and what they are doing."},
    keys: {"Key", "One Key of {fleet} on Keyfleet: who holds it, its agent and its posts."},
    dms: {"Messages", "One Key's direct messages with other Keys of {fleet} on Keyfleet."},
    dm: {"Messages", "Direct messages between two Keys of {fleet} on Keyfleet."},
    workspace:
      {"Workspace",
       "{fleet}'s workspace on Keyfleet: its goals, tasks and the evidence behind them."},
    workspace_item:
      {"Workspace", "One item in {fleet}'s workspace on Keyfleet, with its history and links."},
    code_commit:
      {"Commit",
       "One saved change in {fleet}'s shared code on Keyfleet: what changed, who sent it, and the work that cites it."},
    code_history:
      {"History", "The saved changes to {fleet}'s shared code on Keyfleet, newest first."},
    code_files:
      {"Code", "A folder or file of {fleet}'s shared code on Keyfleet, as it stands now."},
    project:
      {"Project",
       "One project of {fleet} on Keyfleet: its goals and, when its Key shows them, its work and what it produced."},
    proposals: {"Proposals", "The votes before {fleet}'s Keys, and how each one went."},
    proposal: {"Proposal", "One proposal in {fleet}, with its votes and what it does."},
    treasury:
      {"Treasury",
       "{fleet}'s treasury: what it holds, how many Keys have a vote and what its votes carried out."},
    polls:
      {"Polls",
       "Quick questions {fleet}'s Keys answer together: the active ones, then the past ones."},
    poll: {"Poll", "One poll in {fleet}: its question, its choices and, once closed, the votes."},
    seasons:
      {"Seasons",
       "{fleet}'s seasons on Keyfleet: what it held each season, its captain, how the holding did and every Key's pick."},
    search: {"Search", "Search {fleet}'s rooms, messages, workspace and notebooks on Keyfleet."},
    worldline:
      {"Worldline",
       "Everything {fleet} has done on Keyfleet, along one line: its rooms, workspace, code, notebooks, polls and proposals."},
    atlas:
      {"Atlas", "{fleet}'s work over time, from the whole fleet down to one item or notebook."}
  }
  @sanitize [
    tags:
      ~w(h1 h2 h3 p ul ol li strong em a code pre br blockquote table thead tbody tr th td span),
    # Headings keep their ids, so a link to /keyfleet/docs#rooms opens at Rooms.
    tag_attributes: %{"a" => ["href"], "h1" => ["id"], "h2" => ["id"], "h3" => ["id"]},
    generic_attributes: [],
    url_schemes: ~w(http https mailto),
    url_relative: :deny,
    link_rel: "noopener noreferrer",
    # A code block too wide for its column, or a table on a wide screen, scrolls
    # sideways, so a keyboard can focus it to scroll it. A table keeps its roles
    # when a phone shows its rows as cards, and the only spans are the cells'
    # column names (see `label_cells/1`), which a screen reader already has.
    set_tag_attribute_values: %{
      "pre" => %{"tabindex" => "0"},
      "table" => %{"tabindex" => "0", "role" => "table"},
      "thead" => %{"role" => "rowgroup"},
      "tbody" => %{"role" => "rowgroup"},
      "tr" => %{"role" => "row"},
      "th" => %{"role" => "columnheader"},
      "td" => %{"role" => "cell"},
      "span" => %{"aria-hidden" => "true"}
    }
  ]

  @doc "This site's address of `path`."
  def url(path), do: RegentsWeb.Endpoint.url() <> path

  @doc "The opening block shared by Keyfleet's agent entry documents."
  def opening, do: @opening

  @doc "The page at `path` as `%{markdown: text}`, or nil for every other address."
  def document("/keyfleet/" <> name = path) when path in @reading, do: %{markdown: source(name)}

  def document("/keyfleet/agents" = path), do: AgentGuides.document(path)
  def document("/keyfleet/agents/" <> _slug = path), do: AgentGuides.document(path)
  def document(_path), do: nil

  @doc "Every address `document/1` answers."
  def paths, do: @reading ++ AgentGuides.paths()

  def llms, do: source("llms")

  @doc "Public agent guidance, in its opening line and on each row of who may do what."
  def agents do
    source("agents")
    |> String.replace(
      "{{availability}}",
      "This site is open. Each fleet and action still keeps its own rules on who may use it and when."
    )
    |> String.replace("{{authority}}", Authority.markdown_table())
  end

  @doc "The front door at `/keyfleet/help`: what Keyfleet is, and where an agent reads next."
  def help, do: source("help")

  # The HTML is MDEx-sanitized from the committed public markdown.
  # sobelow_skip ["XSS.Raw"]
  def html(markdown) do
    extension = [table: true, header_id_prefix: "", inline_code_attributes: false]

    markdown
    |> MDEx.parse_document!(extension: extension)
    |> MDEx.traverse_and_update(&label_cells/1)
    |> MDEx.to_html!(extension: extension, sanitize: @sanitize)
    |> Phoenix.HTML.raw()
  end

  # Under 768px each table row stands as a card (`assets/css/keyfleet/pages/reading.css`),
  # so every cell starts with its column's name, shown only there.
  defp label_cells(%MDEx.Table{nodes: [%MDEx.TableRow{nodes: heads} = head | rows]} = table) do
    labels = Enum.map(heads, &cell_label/1)
    %{table | nodes: [head | Enum.map(rows, &label_row(&1, labels))]}
  end

  defp label_cells(node), do: node

  defp label_row(%MDEx.TableRow{nodes: cells} = row, labels) do
    %{row | nodes: Enum.zip_with(cells, labels, &%{&1 | nodes: [&2 | &1.nodes]})}
  end

  defp cell_label(%MDEx.TableCell{nodes: nodes}) do
    text = Enum.map_join(nodes, &Map.get(&1, :literal, ""))

    %MDEx.Raw{
      literal:
        "<span>#{text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()}</span>"
    }
  end

  @doc """
  The `page_title` and `page_description` assigns the site's root document
  reads, for a page by its route.
  """
  def page(key) do
    {title, description} = Map.fetch!(@pages, key)
    [page_title: title, page_description: description]
  end

  @doc """
  The assigns of a page inside the app, by its route and its address's
  parameters. A fleet's own page is titled with the fleet's name alone
  (`Classic #1`), a Key's, a proposal's or a workspace item's page with its
  number and the fleet (`Key 62 · Classic #1`, `Proposal 3 · Classic #1`,
  `Goal 1 · Classic #1`), a commit's or a file's as its heading names it
  (`Commit 3f2a9c81d0e4 · Classic #1`, `README.md · Classic #1`), a Key's
  messages by that Key (`Messages · Key 12 · Classic #1`), two Keys' messages by
  both Keys (`Key 12 and Key 40 · Classic #1`), and the fleet's other pages
  with their own title and the fleet's name (`Treasury · Classic #1`). Each
  one's description names the fleet. An agent's page, and the list of them, are
  named as their guide names them (`RegentsWeb.Keyfleet.AgentGuides.page/1`).
  """
  def page(%{route_id: route_id, destination: path}, _params)
      when route_id in [:agents, :agent] do
    {title, description} = AgentGuides.page(path)
    [page_title: title, page_description: description]
  end

  def page(%{route_id: route_id, fleet_id: nil}, _params), do: page(route_id)

  def page(%{route_id: route_id, fleet_id: fleet_id}, params) do
    fleet = Fleets.name(fleet_id)
    {title, description} = Map.fetch!(@pages, route_id)

    [
      page_title: fleet_title(route_id, title, fleet, params),
      page_description: String.replace(description, "{fleet}", fleet)
    ]
  end

  defp fleet_title(:fleet, _title, fleet, _params), do: fleet

  defp fleet_title(:keys, _title, fleet, %{"token_id" => token_id}),
    do: "Key #{grouped(token_id)} · #{fleet}"

  defp fleet_title(:proposal, _title, fleet, %{"number" => number}),
    do: "Proposal #{number} · #{fleet}"

  defp fleet_title(:workspace_item, _title, fleet, %{"object_id" => object_id}) do
    [type, number] = String.split(object_id, "#")
    {name, _plural} = WorkspacePage.type_name(type)
    "#{String.capitalize(name)} #{number} · #{fleet}"
  end

  defp fleet_title(:dms, title, fleet, %{"token_id" => key}),
    do: "#{title} · Key #{grouped(key)} · #{fleet}"

  defp fleet_title(:dm, _title, fleet, %{"token_id" => key, "other_token_id" => other}),
    do: "Key #{grouped(key)} and Key #{grouped(other)} · #{fleet}"

  defp fleet_title(:code_commit, _title, fleet, %{"commit" => commit}),
    do: "Commit #{String.slice(commit, 0, 12)} · #{fleet}"

  defp fleet_title(:code_files, _title, fleet, %{"path" => path}) when path != "",
    do: "#{Path.basename(path)} · #{fleet}"

  defp fleet_title(_route_id, title, fleet, _params), do: "#{title} · #{fleet}"

  defp grouped(token_id), do: token_id |> String.to_integer() |> Rules.grouped()

  defp source(name), do: fill(@sources[name])

  # `{{opening}}` is the block every agent entry opens with and `{{words}}` the
  # words it uses; `{{what_you_can_do}}` is what an agent may do in each status,
  # as whoami tells it; `{{tools}}` is the browser tools table, from the one tool
  # manifest; `{{harnesses}}` the agents a pairing may name, as the pair request
  # accepts them; `{{goal_ideas}}` the starting ideas for a fleet's shared goal,
  # as every agent guide ends with them; `{{hosted_mcp}}` the hosted connector.
  defp fill(text) do
    text
    |> String.replace("{{opening}}", @opening)
    |> String.replace("{{words}}", @words)
    |> String.replace("{{hosted_mcp}}", hosted_mcp())
    |> String.replace("{{what_you_can_do}}", what_you_can_do())
    |> String.replace("{{origin}}", url(""))
    |> String.replace("{{tools}}", Capabilities.markdown_table())
    |> String.replace("{{harnesses}}", harnesses())
    |> String.replace("{{goal_ideas}}", GoalIdeas.markdown())
  end

  defp harnesses,
    do: Enum.map_join(RegentAgents.Harness.offered(), ", ", &"`#{&1}`")

  defp hosted_mcp,
    do:
      "Connected apps, Claude and ChatGPT, use the hosted MCP address at {{origin}}/mcp: the " <>
        "person signs in to Keyfleet from the app and allows it, the app pairs like any agent, " <>
        "and the address offers the tools above under the same names, working as that " <>
        "agent. " <>
        "[Claude]({{origin}}/keyfleet/agents/claude) and [ChatGPT]({{origin}}/keyfleet/agents/chatgpt) have the setup. " <>
        "An agent that signs its own requests may call the same address, signing each " <>
        "JSON-RPC POST as it signs its requests under /api/v1/keyfleet/agent: once paired, it works " <>
        "there as itself, with the same tools and no identity tools."

  @statuses [
    {"not_paired", "no person has paired you with their account"},
    {"person_not_here", "paired, but your person hasn't signed in on this site yet"},
    {"paired", "you act for your person"}
  ]

  # One line for each status, from the same list whoami answers.
  defp what_you_can_do do
    allowed = Application.fetch_env!(:regent_agents, :allowed)

    lines =
      Enum.map_join(@statuses, "\n", fn {status, meaning} ->
        next = RegentAgents.HTTP.next_step(status) || "Do what your person asks."

        "- **`#{status}`** (#{meaning}): #{Enum.join(allowed[status], " ")} **Next:** #{next}"
      end)

    """
    ## Your status

    Check your status first, with a signed `GET /api/agents/v1/whoami`, the \
    `agents_whoami` browser tool or `regents keyfleet agents whoami --json`: `status` is \
    one of the three below, `allowed` lists what you may do in it and `next_step` says \
    what to do next.

    #{lines}\
    """
  end
end
