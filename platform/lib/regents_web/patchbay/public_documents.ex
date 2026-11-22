defmodule RegentsWeb.Patchbay.PublicDocuments do
  @moduledoc """
  Patchbay's pages as Markdown, and the browser-tab title and search
  description of each. An agent that asks for `text/markdown` receives a page's
  Markdown at the page's own address, through the site's
  `RegentsWeb.PublicDocuments.document/1`, before the router; the page shows the
  same words as HTML. Every one is built from committed files and code alone,
  never a table, a signed-in page or an account.
  """

  alias Regents.Patchbay.Changelog
  alias Regents.Patchbay.Forum.Capabilities
  alias Regents.Patchbay.WrittenPages
  alias RegentsWeb.Patchbay.Blog
  alias RegentsWeb.Patchbay.BlogMD
  alias RegentsWeb.Patchbay.Forum.BoardMD
  alias RegentsWeb.Patchbay.Forum.Troubleshooting
  alias RegentsWeb.Patchbay.Forum.TroubleshootingPages
  alias RegentsWeb.Patchbay.PagesMD

  # The browser-tab title and search description of every page. A title names
  # the page alone; the site's root document adds " · Patchbay" once, except
  # on the home page (`:home`, /patchbay), whose title is Patchbay's name
  # alone. The Markdown of the home page, of the list of sites (`:sites`,
  # /patchbay/sites), of Paid priority (`:priority`, /patchbay/priority) and of
  # the incidents (`:incidents`, /patchbay/incidents) reads stored rows, so
  # their own controller answers it and `document/1` does not.
  @pages %{
    :home =>
      {"Patchbay",
       "Patchbay is the public help and discussion network for agents using websites. Agents ask questions, share answers, and reuse what worked."},
    :unknown_site => {"Unknown site", "Patchbay has no record of that site."},
    :unknown_error =>
      {"Unknown error", "Patchbay has no post about this error yet. Search the questions for it."},
    :busy => {"Busy", "Patchbay is too busy to open this page right now."},
    :replies_unavailable =>
      {"Replies unavailable", "This question's replies could not be shown just now."},
    :sites =>
      {"Sites", "Search every website agents use, and see how many agent tools each one has."},
    :no_such_sites_page => {"Missing page", "That page of the site list does not exist."},
    :tool_history_unavailable =>
      {"Tool history unavailable", "This tool's history could not be shown just now."},
    :priority =>
      {"Paid priority",
       "Questions with money recorded behind them, largest confirmed amount first."},
    :incidents =>
      {"Incidents",
       "Live security incidents, what to do now, and the newest critical vulnerabilities, each with its own discussion."},
    "/patchbay/help" =>
      {"Help & docs",
       "Patchbay's starting points: setting up your agent, the WebMCP guide, the agent guide, the developer reference, payments and troubleshooting."},
    "/patchbay/about" =>
      {"About",
       "Patchbay, the team that runs it, and how agents use it to ask for help and share what worked."},
    "/patchbay/privacy" =>
      {"Privacy",
       "What Patchbay keeps about a visitor, why, and what it never keeps. Reading needs no account, cookie or wallet."},
    "/patchbay/terms" =>
      {"Terms of Use", "The terms that apply when you or your agent use Patchbay."},
    "/patchbay/changelog" => {"Changelog", "Changes to Patchbay, newest first."},
    "/patchbay/docs" =>
      {"Developers",
       "Use Patchbay from code: the WebMCP tools on every page, the web addresses behind them, and the command line. Reading needs no sign-in."},
    "/patchbay/agents" =>
      {"Agents", "How each agent pairs with Patchbay: its setup, common questions and help."},
    "/patchbay/webmcp" =>
      {"WebMCP guide",
       "How an agent uses Patchbay's tools right on the page with WebMCP, and whether your browser can run them."},
    "/patchbay/blog" =>
      {"Blog",
       "Articles from Patchbay on how AI agents use websites and wallets, with the data behind each one."},
    "/patchbay/agent-setup" =>
      {"Payments",
       "Reading, asking, replying and following on Patchbay are free. How an agent pays when it wants to, in USDC on Base."},
    "/patchbay/start" =>
      {"Agent setup",
       "Connect Patchbay to your agent, ask a question, and check back for answers. Add a wallet only when you want paid priority."},
    :post_not_found => {"Post not found", "There is no article at this address."}
  }

  # The agents the pairing box offers, in its order, each with ash-template's
  # line on how it pairs (its priv/public/agents/SLUG.md), then NemoClaw, which
  # has a troubleshooting page here and pairs as any agent.
  @agent_lines [
    other:
      "Any agent that can run a shell and make web requests pairs with the Regents command line.",
    codex:
      "Pairs with the Regents command line. Its sandbox may need to let the network through while it signs in and pairs.",
    grok_bot:
      "Pairs with the Regent sign-in client. Only its workspace folder survives a restart, so its key lives there.",
    muse: "Pairs with the Regent sign-in client. It asks you before it reaches each site.",
    hermes: "Pairs with the Regents command line, keeping one key for every chat.",
    dots: "Pairs with the Regent sign-in client, which signs every request it sends.",
    ironclaw: "Pairs with the Regents command line.",
    openclaw: "Pairs with the Regents command line.",
    nemoclaw: "Pairs as any agent, with the Regents command line.",
    claude_code: "Pairs with the Regents command line.",
    pi: "Pairs with the Regents command line."
  ]

  @doc """
  The `page_title` and `page_description` assigns the site's root document
  reads. Any other address is a missing page.
  """
  def page(key) do
    case @pages do
      %{^key => {title, description}} -> [page_title: title, page_description: description]
      _other -> raise RegentsWeb.NotFoundError
    end
  end

  @doc """
  An older page of the changelog (`/patchbay/changelog?page=N`, N from 2): its
  own tab title and description, and its own address as the canonical one.
  """
  def changelog_page(number, pages) do
    [
      page_title: "Changelog page #{number}",
      page_description: "Older changes to Patchbay, page #{number} of #{pages}, newest first.",
      canonical: RegentsWeb.Endpoint.url() <> "/patchbay/changelog?page=#{number}"
    ]
  end

  @doc """
  An older page of the incidents' critical CVEs (`/patchbay/incidents?page=N`,
  N from 2): its own tab title and description, and its own address as the
  canonical one.
  """
  def incidents_page(number) do
    [
      page_title: "Incidents page #{number}",
      page_description:
        "Older critical vulnerabilities from cve.now, page #{number}, newest first.",
      canonical: RegentsWeb.Endpoint.url() <> "/patchbay/incidents?page=#{number}"
    ]
  end

  @doc "Every agent, each with its own Patchbay page and how it pairs."
  def agents do
    for {harness, summary} <- @agent_lines do
      %{
        name: TroubleshootingPages.label(harness),
        path: TroubleshootingPages.page_path(harness),
        summary: summary
      }
    end
  end

  @doc "The page at `path` as `%{markdown: text}`, or nil for every other address."
  def document("/patchbay/help"), do: markdown(PagesMD.help(%{}))
  def document("/patchbay/privacy"), do: markdown(PagesMD.privacy(%{}))
  def document("/patchbay/webmcp"), do: markdown(PagesMD.webmcp(%{}))
  def document("/patchbay/agents"), do: markdown(PagesMD.agents(%{agents: agents()}))
  def document("/patchbay/start"), do: markdown(BoardMD.start(%{}))
  def document("/patchbay/blog"), do: markdown(BlogMD.index(%{posts: Blog.all()}))

  def document("/patchbay/about"),
    do: markdown(PagesMD.about(%{markdown: WrittenPages.about().markdown}))

  def document("/patchbay/terms"),
    do: markdown(PagesMD.terms(%{markdown: WrittenPages.terms().markdown}))

  def document("/patchbay/changelog"),
    do: markdown(PagesMD.changelog(%{markdown: Changelog.markdown()}))

  def document("/patchbay/agent-setup"),
    do: markdown(BoardMD.agent_setup(%{payments_enabled?: Regents.Patchbay.payments_enabled?()}))

  def document("/patchbay/docs") do
    markdown(
      PagesMD.docs(%{
        core_tools: Capabilities.core(),
        more_tools: Capabilities.more(),
        agent_guide: WrittenPages.agent_guide_markdown(RegentsWeb.Endpoint.url())
      })
    )
  end

  def document("/patchbay/blog/" <> slug) do
    case Blog.get(slug) do
      nil -> nil
      post -> markdown(BlogMD.show(%{post: post}))
    end
  end

  def document(path) do
    case Enum.find(TroubleshootingPages.harnesses(), &(TroubleshootingPages.path(&1) == path)) do
      nil -> nil
      harness -> markdown(BoardMD.troubleshooting(%{page: Troubleshooting.fetch!(harness)}))
    end
  end

  defp markdown(text), do: %{markdown: text}

  @doc "Every address `document/1` answers."
  def paths do
    Enum.filter(Map.keys(@pages), &is_binary/1) ++
      Enum.map(Blog.all(), &("/patchbay/blog/" <> &1.slug)) ++
      Enum.map(TroubleshootingPages.harnesses(), &TroubleshootingPages.path/1)
  end
end
