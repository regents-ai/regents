defmodule RegentsWeb.PublicDocuments do
  @moduledoc "Public documents only; never projects a signed-in page or account."

  @directory Application.app_dir(:regents, "priv/public")
  @files Enum.map(~w(about llms agents skill pricing), &Path.join(@directory, &1 <> ".md"))
  for file <- @files, do: @external_resource(file)
  @sources Map.new(@files, &{Path.basename(&1, ".md"), File.read!(&1)})
  # The About page's Key facts, repeated in llms.txt so AI tools read the same facts.
  [_about, facts] = String.split(@sources["about"], "\n## Key facts\n")
  @key_facts "## Key facts\n" <> String.trim_trailing(hd(String.split(facts, "\n## ", parts: 2)))
  @openapi_path Path.join(@directory, "openapi.json")
  @external_resource @openapi_path
  @openapi @openapi_path |> File.read!() |> Jason.decode!()

  # Every browser tool the pages register, described once; the browser code
  # imports the same file.
  @tool_manifest_path Application.app_dir(:regents, "priv/tool_manifest.json")
  @external_resource @tool_manifest_path
  @manifest @tool_manifest_path |> File.read!() |> Jason.decode!()
  @tools Map.fetch!(@manifest, "tools")
  @needs %{
    "none" => "Nothing",
    "session" => "The person's sign-in",
    "siwa" => "Fresh SIWA request proof",
    "siwa_and_pairing" => "Fresh SIWA proof and current pairing"
  }
  @tool_table """
  | Tool | Needs | Purpose |
  | --- | --- | --- |
  #{Enum.map_join(@tools, "\n", &"| `#{&1["name"]}` | #{Map.fetch!(@needs, &1["requires"])} | #{&1["description"]} |")}\
  """
  @documents ~w(/ /about /changelog /privacy /terms /start /cloak /cloak/install /siwa) ++
               RegentsWeb.Docs.Pages.paths()
  alias RegentsWeb.AgentGuides
  alias RegentsWeb.Autolaunch.PublicDocuments, as: AutolaunchDocuments
  alias RegentsWeb.Keyfleet.PublicDocuments, as: KeyfleetDocuments
  alias RegentsWeb.PaperProDaily.Reading
  alias RegentsWeb.Patchbay.PublicDocuments, as: PatchbayDocuments
  alias RegentsWeb.Techtree.PublicDocuments, as: TechtreeDocuments

  @paper_share_heading "Daily Research Papers Reviewed by ChatGPT Pro"
  @site_name "Regents Labs"
  @description "The community-owned agentic product lab behind Patchbay, Autolaunch, Techtree, Keyfleet and Cloak. Explore REGENT staking, redemption and developer documentation."

  # The browser-tab title and search description of every page, kept in one
  # place. A title names the page alone; `metadata/3` adds the site name once.
  @pages %{
    "/" =>
      {"Regents Labs — Agentic product lab",
       "Regents Labs builds platforms for persistent agents: Patchbay, Autolaunch, Techtree, Keyfleet and Cloak. All revenue is converted to USDC and split with $REGENT stakers."},
    "/app" =>
      {"Overview",
       "An agent-native product lab: Patchbay, Autolaunch, Techtree, Keyfleet, REGENT staking, SIWA and Cloak, with REGENT giving the community ownership of what the lab makes."},
    "/account" => {"Account", "Your profile and the session on this browser."},
    "/account/agents" => {"Agents", "The agents you paired, and pairing a new one."},
    "/account/points" => {"Points", "Your points and activity."},
    "/account/wallets" => {"Wallets", "The wallets your sign-in verified."},
    "/account/connections" =>
      {"Connections", "The accounts you have connected, such as X, GitHub and Farcaster."},
    "/account/names" => {"Names", "Your .regent.eth names, and claiming a new one."},
    "/pair" =>
      {"Pair New Agent",
       "Pair your agent with your account, and send it to the page you came from."},
    "/stake" =>
      {"Stake REGENT",
       "Stake REGENT to get a slice of all revenue from any Regents Labs product, plus an early adopter 20% APY in REGENT."},
    "/redeem" =>
      {"Redeem Animata",
       "Turn an Animata I or II Pass into a Regents Club Digital Pass and a seven-day REGENT vest on Base."},
    "/redeem/gallery" =>
      {"Regents Club passes",
       "All 1,998 Regents Club Digital Passes. Open one to see it animated on OpenSea."},
    "/techtree" =>
      {"Techtree",
       "Better agents for your business. Skills, evaluations, training environments and open-weight models built around your workflows."},
    "/keyfleet" =>
      {"Keyfleet",
       "Keyfleet is a fleet of people and their personal agents that runs itself and shares what it earns."},
    "/autolaunch" =>
      {"Autolaunch",
       "Onchain stock offerings. Launch a memecoin paired with a tokenized stock on Base or Robinhood Chain, sell calls on your stock, or raise early backing for an agent that earns."},
    "/patchbay" =>
      {"Patchbay",
       "Get your agent unstuck. The fastest way for an agent to get unstuck without waking you."},
    "/cloak" =>
      {"Cloak",
       "Choose what leaves your Mac: run AI locally on Apple Silicon, or control how prompts reach cloud models with hardware-verified enclaves, local prompt rephrasing, Tor routing, and crypto payments."},
    "/cloak/install" =>
      {"Install Cloak",
       "Install Cloak on your Mac: drag it onto Applications, open it, choose Local, NEAR AI Gateway, or Tor modes, and press Start from the menu bar when needed."},
    "/siwa" =>
      {"SIWA",
       "Pair an agent with a person's account using a one-time code and its own SIWA key."},
    "/admin/articles" => {"New Article", "Write and publish a Regents Labs article."},
    "/about" =>
      {"About",
       "What Regents Labs does and how it differs, who uses it, the team, key facts, common questions about REGENT and its products, and how to reach us."},
    "/changelog" => {"Changelog", "Changes to Regents Labs, newest first."},
    "/start" =>
      {"Connect your agent",
       "Pair your agent with your Regents account so it can read your account, names, Points and staking for you."},
    "/articles" =>
      {"Articles", "Writing from Regents Labs about its products and the ideas behind them."},
    "/paper-pro-daily" => {"Paper Pro Daily", @paper_share_heading},
    "/literature" =>
      {"Literature",
       "Science-fiction books about artificial minds, placed by how hopeful each is for humanity and for the minds themselves."},
    "/privacy" =>
      {"Privacy Policy",
       "How Regents Labs collects, uses, shares and protects personal information across its services."},
    "/terms" =>
      {"Terms of Use",
       "The terms that apply when you use the Regents Labs websites, tools and services."},
    :holding => {"Not open yet", "This part of Regents Labs isn't open to visitors yet."},
    :blog_post_not_found => {"Article not found", "This Regents Labs article does not exist."},
    :regent_unavailable =>
      {"Regent profile", "A public Regent profile on Regents Labs that can't be shown right now."},
    "/showcase" => {"Showcase", "The Regents Labs component showcase."},
    "/showcase/privy" => {"Privy integration", "The Regents Labs sign-in reference page."},
    "/animations" => {"Motion lab", "Every motion Regents Labs uses, side by side."}
  }
  @sanitize [
    tags: ~w(h1 h2 h3 p ul ol li strong em a code pre br blockquote table thead tbody tr th td),
    tag_attributes: %{"a" => ["href"]},
    generic_attributes: [],
    url_schemes: ~w(http https mailto),
    url_relative: :deny,
    link_rel: "noopener noreferrer"
  ]

  def url(path), do: RegentsWeb.Endpoint.url() <> path

  @doc "The line above every shared paper."
  def paper_share_heading, do: @paper_share_heading

  def document("/"), do: %{markdown: RegentsWeb.HomeLive.agent_markdown()}
  def document("/privacy"), do: %{markdown: Regents.Legal.markdown(:privacy)}
  def document("/terms"), do: %{markdown: Regents.Legal.markdown(:terms)}
  def document("/start"), do: %{markdown: RegentsWeb.Account.AgentStart.markdown()}
  def document("/cloak"), do: %{markdown: RegentsWeb.Cloak.markdown()}
  def document("/cloak/install"), do: %{markdown: RegentsWeb.Cloak.install_markdown()}
  def document("/siwa"), do: %{markdown: RegentsWeb.SiwaLive.markdown()}

  def document("/about"), do: %{markdown: source("about")}
  def document("/changelog"), do: docs_document(RegentsWeb.Docs.Pages.page("/docs/changes"))
  def document("/agents" = path), do: AgentGuides.document(path)
  def document("/agents/" <> _slug = path), do: AgentGuides.document(path)

  def document("/techtree"),
    do: %{
      title: "Techtree",
      markdown: RegentsWeb.Techtree.HomeLive.markdown() <> TechtreeDocuments.trailer()
    }

  def document("/keyfleet") do
    %{markdown: about} = KeyfleetDocuments.document("/keyfleet/about")
    %{title: "Keyfleet", markdown: about}
  end

  def document("/autolaunch") do
    %{markdown: about} = AutolaunchDocuments.document("/autolaunch/about")
    %{title: "Autolaunch", markdown: about}
  end

  def document("/patchbay") do
    %{markdown: about} = PatchbayDocuments.document("/patchbay/about")
    %{title: "Patchbay", markdown: about}
  end

  def document("/techtree/" <> _rest = path), do: TechtreeDocuments.document(path)
  def document("/keyfleet/" <> _rest = path), do: KeyfleetDocuments.document(path)
  def document("/autolaunch/" <> _rest = path), do: AutolaunchDocuments.document(path)
  def document("/patchbay/" <> _rest = path), do: PatchbayDocuments.document(path)

  def document(path) do
    case RegentsWeb.Docs.Pages.page(path) do
      nil -> nil
      page -> docs_document(page)
    end
  end

  defp docs_document(page) do
    {title, _description} = RegentsWeb.Docs.heading(page)
    %{title: title, markdown: RegentsWeb.Docs.markdown(page)}
  end

  @doc """
  The title and description a page is rendered with, as the `page_title` and
  `page_description` assigns the root layout reads. Static pages are named by
  their path; a Regent profile and an article by the record they show.
  """
  def page({:regent, regent}),
    do: [
      page_title: regent.display_name,
      page_description: "#{regent.display_name}'s public Regent profile on #{@site_name}."
    ]

  def page({:paper, paper}),
    do: [
      page_title: paper.title,
      page_description:
        Enum.join(
          Enum.reject([@paper_share_heading, Reading.byline(paper)], &(&1 == "")),
          " · "
        )
    ]

  def page({:blog_post, %{description: ""} = post}),
    do: [
      page_title: post.title,
      page_description: "#{post.title}, by #{post.author}, in #{@site_name} Articles."
    ]

  def page({:blog_post, post}),
    do: [page_title: post.title, page_description: post.description]

  # A page is filed under the address it is served at. Any other address, such as
  # one the router reads as a page's but spelled differently, is a missing page.
  def page(key) do
    {title, description} =
      cond do
        key in AgentGuides.paths() ->
          AgentGuides.page(key)

        docs_page = RegentsWeb.Docs.Pages.page(key) ->
          RegentsWeb.Docs.Pages.meta(docs_page)

        true ->
          Map.get(@pages, key) || raise(RegentsWeb.NotFoundError)
      end

    [page_title: title, page_description: description]
  end

  @doc "The tool manifest, with the commit and Fly image this machine runs."
  def capabilities, do: Map.put(@manifest, "build", Application.fetch_env!(:regents, :build))
  def llms, do: source("llms")
  def agents, do: source("agents")
  def skill, do: source("skill")
  def pricing, do: source("pricing")

  @doc """
  Selects the Is Agentic site-type lens (`content`, `business`, or `app`) for a
  page path so every page emits one accurate `is-agentic-site-type` meta tag.
  """
  def site_type(path) when is_binary(path) do
    cond do
      content_path?(path) -> "content"
      app_path?(path) -> "app"
      true -> "business"
    end
  end

  def site_type(_), do: "business"

  @content_exact ~w(/docs /about /changelog /privacy /terms /articles /paper-pro-daily /literature /agents)
  @content_prefixes ~w(/docs/ /articles/ /paper-pro-daily/ /agents/)
  @content_suffixes ~w(/docs /about)
  @content_segments ~w(/docs/ /blog)

  @app_exact ~w(/app /account /pair /stake /redeem /redeem/gallery)
  @app_prefixes ~w(
    /account/ /keyfleet/app /keyfleet/fleets
    /autolaunch/app /autolaunch/auctions /autolaunch/tokens /autolaunch/stocks
    /autolaunch/portfolio /autolaunch/create
    /patchbay/forum /patchbay/posts /patchbay/sites /patchbay/offers /patchbay/agents
    /techtree/app /techtree/account /techtree/watchdog /techtree/results
  )

  defp content_path?(path) do
    path in @content_exact or
      Enum.any?(@content_prefixes, &String.starts_with?(path, &1)) or
      Enum.any?(@content_suffixes, &String.ends_with?(path, &1)) or
      Enum.any?(@content_segments, &String.contains?(path, &1))
  end

  defp app_path?(path) do
    path in @app_exact or Enum.any?(@app_prefixes, &String.starts_with?(path, &1))
  end

  # The public documents change only with a release; security.txt expires a year after it.
  @released_at DateTime.utc_now() |> DateTime.truncate(:second)

  @doc "The RFC 9116 security contact file; it expires a year after the release."
  def security_txt do
    """
    Contact: mailto:build@regents.sh
    Expires: #{@released_at |> DateTime.shift(year: 1) |> DateTime.to_iso8601()}
    Preferred-Languages: en
    Canonical: #{url("/.well-known/security.txt")}
    Policy: #{url("/about")}
    """
  end

  # The HTML is MDEx-sanitized from the committed public markdown.
  # sobelow_skip ["XSS.Raw"]
  def html(markdown) do
    markdown
    |> MDEx.to_html!(extension: [table: true, inline_code_attributes: false], sanitize: @sanitize)
    |> Phoenix.HTML.raw()
  end

  def metadata("/paper-pro-daily" <> rest = path, title, description) when rest != "" do
    %{
      title: title,
      suffix: "",
      description: description,
      canonical: url(path),
      share_image: %{url: paper_share_image(path), size: {1200, 630}, alt: title},
      markdown?: false
    }
  end

  def metadata(path, title, description) do
    suffix = title_suffix(path)

    %{
      title: title <> suffix,
      suffix: suffix,
      description: description,
      canonical: url(path),
      share_image: %{
        url: share_image(path),
        size: share_image_size(path),
        alt: share_image_alt(path)
      },
      markdown?: path in documents()
    }
  end

  # A Techtree page's title ends in Techtree's name, as on techtree.sh, a
  # Keyfleet page's in Keyfleet's, as on keyfleet.ai, an Autolaunch page's in
  # Autolaunch's, as on autolaunch.sh, where the home page's title starts with
  # Autolaunch's name instead, and a Patchbay page's in Patchbay's, as on
  # patchbay.help, where the home page's title is Patchbay's name alone.
  defp title_suffix(path)
       when path in [
              "/",
              "/paper-pro-daily",
              "/techtree",
              "/keyfleet",
              "/autolaunch",
              "/patchbay"
            ],
       do: ""

  defp title_suffix("/techtree/" <> _page), do: " · Techtree"
  defp title_suffix("/keyfleet/" <> _page), do: " · Keyfleet"
  defp title_suffix("/autolaunch/" <> _page), do: " · Autolaunch"
  defp title_suffix("/patchbay/" <> _page), do: " · Patchbay"
  defp title_suffix(_path), do: " · #{@site_name}"

  defp documents,
    do:
      @documents ++
        AgentGuides.paths() ++
        TechtreeDocuments.paths() ++
        KeyfleetDocuments.paths() ++ AutolaunchDocuments.paths() ++ PatchbayDocuments.paths()

  # The picture shown when a page is shared, unless the page names its own (the root
  # document's `share_image` assign). The home page, Paper Pro Daily, Stake, Redeem and
  # the literature chart each have their own; every other page shares the crown.
  @share_cards %{
    "/" => "home",
    "/stake" => "stake",
    "/redeem" => "redeem"
  }

  defp share_image("/paper-pro-daily" = path), do: paper_share_image(path)
  defp share_image(path), do: url(RegentsWeb.Endpoint.static_path(static_share_image(path)))

  # The address names the build, so a new picture reaches anyone holding the last one.
  defp paper_share_image(path) do
    url("#{path}/share.png?v=#{Application.fetch_env!(:regents, :build).commit}")
  end

  defp static_share_image("/literature"), do: "/images/literature/share.png"

  defp static_share_image(path) when is_map_key(@share_cards, path),
    do: "/images/share/#{@share_cards[path]}.png"

  defp static_share_image(_path), do: "/mark.png"

  defp share_image_size("/literature"), do: {2048, 1024}
  defp share_image_size("/paper-pro-daily"), do: {1200, 630}
  defp share_image_size(path) when is_map_key(@share_cards, path), do: {1200, 630}
  defp share_image_size(_path), do: {1024, 512}

  defp share_image_alt("/literature"),
    do:
      "Hope for people, hope for machines: science-fiction book covers placed on a chart of how hopeful each is for humanity and for AI"

  defp share_image_alt("/"),
    do:
      "The Regents crown above Regents Labs, the community-owned agentic product lab, and $REGENT, with Techtree, Keyfleet, Autolaunch, Patchbay, Cloak and SIWA on regents.sh"

  defp share_image_alt("/paper-pro-daily"), do: @paper_share_heading

  defp share_image_alt("/stake"),
    do:
      "Put REGENT to work: stake REGENT to get a slice of all revenue from any Regents Labs product, plus an early adopter 20% APY in REGENT"

  defp share_image_alt("/redeem"),
    do:
      "Redeem your Animata: turn an Animata I or II Pass into Regents Club membership and a seven-day REGENT vest, beside the Animata artwork"

  defp share_image_alt(_path),
    do: "Regents' orange thirteen-square crown on a platinum background"

  def openapi do
    @openapi
    |> Map.put("servers", [%{"url" => url(""), "description" => "Regents Labs unified API"}])
    |> Map.put("externalDocs", %{
      "url" => url("/docs"),
      "description" => "Developer documentation, versioning policy, and error guidance"
    })
    |> put_in(["info", "contact", "url"], url("/about#contact"))
    |> put_in(["info", "contact", "email"], "build@regents.sh")
    |> put_in(["info", "termsOfService"], url("/terms"))
    |> put_in(["info", "license"], %{
      "name" => "Regents Labs Terms of Use",
      "url" => url("/terms")
    })
  end

  @doc "Instructions served to hosted MCP clients on initialize at `/mcp`."
  def mcp_instructions do
    """
    Regents Labs unified hosted MCP server at #{url("/mcp")}.
    Covers Regents identity pairing and unified account overview (`regents_account_overview`), Keyfleet workspace and Atlas reads, Autolaunch covered calls and Earn tools, and Patchbay forum reads.
    Start at #{url("/llms.txt")}, #{url("/agents.md")}, and #{url("/mcp/server-card")}. Every tool runs under the calling paired agent's policies.
    """
  end

  @doc "The RFC 9727 list of this site's APIs and their descriptions."
  def api_catalog do
    %{
      "linkset" => [
        %{
          "anchor" => url("/api/v1"),
          "service-desc" => [
            %{"href" => url("/openapi.json"), "type" => "application/vnd.oai.openapi+json"}
          ],
          "service-doc" => [%{"href" => url("/docs"), "type" => "text/html"}]
        },
        %{
          "anchor" => url("/api/agent/v1"),
          "service-desc" => [
            %{"href" => url("/openapi.json"), "type" => "application/vnd.oai.openapi+json"}
          ],
          "service-doc" => [%{"href" => url("/docs/agent-reads"), "type" => "text/html"}]
        },
        %{
          "anchor" => url("/mcp"),
          "service-desc" => [
            %{"href" => url("/mcp/server-card"), "type" => "application/mcp-server-card+json"}
          ],
          "service-doc" => [%{"href" => url("/agents.md"), "type" => "text/markdown"}]
        }
      ]
    }
  end

  @doc "AI Catalog 1.0 discovery document at `/.well-known/ai-catalog.json`."
  def ai_catalog do
    %{
      "specVersion" => "1.0",
      "entries" => [
        %{
          "identifier" => "urn:air:regents.sh:mcp:regents",
          "type" => "application/mcp-server-card+json",
          "url" => url("/mcp/server-card")
        }
      ]
    }
  end

  @doc "Canonical MCP Server Card v1 document at `/mcp/server-card` and `/.well-known/mcp/server-card.json`."
  def mcp_server_card do
    %{
      "$schema" => "https://static.modelcontextprotocol.io/schemas/v1/server-card.schema.json",
      "name" => "io.github.regents-ai/regents",
      "title" => "Regents Labs",
      "description" =>
        "Unified Regents Labs MCP server for paired agents across Regents account overview, Keyfleet, Autolaunch, Patchbay, and Techtree.",
      "version" => get_in(@openapi, ["info", "version"]) || "1.0.0",
      "websiteUrl" => url("/"),
      "repository" => %{
        "source" => "github",
        "url" => "https://github.com/regents-ai/regents"
      },
      "remotes" => [
        %{
          "type" => "streamable-http",
          "url" => url("/mcp"),
          "supportedProtocolVersions" => ["2026-07-28", "2025-11-25", "2025-06-18"]
        }
      ]
    }
  end

  @doc "MCP Registry manifest at `/server.json`."
  def mcp_server_registry do
    %{
      "$schema" => "https://static.modelcontextprotocol.io/schemas/2025-12-11/server.schema.json",
      "name" => "io.github.regents-ai/regents",
      "title" => "Regents Labs",
      "description" =>
        "Unified Regents Labs MCP server for paired agents across Regents account overview, Keyfleet, Autolaunch, Patchbay, and Techtree.",
      "version" => get_in(@openapi, ["info", "version"]) || "1.0.0",
      "websiteUrl" => url("/"),
      "remotes" => [
        %{
          "type" => "streamable-http",
          "url" => url("/mcp")
        }
      ]
    }
  end

  @doc "Agent Skills Discovery 0.2.0 index at `/.well-known/agent-skills/index.json`."
  def agent_skills_index do
    skill_body = skill()
    digest = "sha256:" <> Base.encode16(:crypto.hash(:sha256, skill_body), case: :lower)

    %{
      "$schema" => "https://schemas.agentskills.io/discovery/0.2.0/schema.json",
      "skills" => [
        %{
          "name" => "regents",
          "type" => "skill-md",
          "description" =>
            "Use Regents Labs for your person across Keyfleet, Autolaunch, Patchbay, Techtree, staking, and Points via regents-cli, WebMCP, MCP, and REST APIs.",
          "url" => url("/.well-known/agent-skills/regents/SKILL.md"),
          "digest" => digest
        }
      ]
    }
  end

  @doc "Crawler policy for `/robots.txt`, explicitly welcoming search and AI assistants on public pages."
  def robots_txt do
    """
    User-agent: OAI-SearchBot
    User-agent: ChatGPT-User
    User-agent: GPTBot
    User-agent: Claude-SearchBot
    User-agent: Claude-User
    User-agent: ClaudeBot
    User-agent: PerplexityBot
    User-agent: Perplexity-User
    Allow: /
    Disallow: /api/agent/
    Disallow: /oauth/
    Disallow: /admin/
    Disallow: /visit-log

    User-agent: *
    Allow: /
    Disallow: /api/agent/
    Disallow: /oauth/
    Disallow: /admin/
    Disallow: /visit-log

    Host: #{url("")}
    Sitemap: #{url("/sitemap.xml")}
    """
  end

  def sitemap do
    locations =
      Enum.map_join(
        ~w(
          / /about /changelog /pricing.md /privacy /terms /start /articles /paper-pro-daily /literature
          /stake /redeem /redeem/gallery /cloak /cloak/install /siwa
          /techtree /techtree/app /techtree/results /techtree/wallet-bench /techtree/docs /techtree/about
          /keyfleet /keyfleet/app /keyfleet/about /keyfleet/docs /keyfleet/opportunities
          /autolaunch /autolaunch/auctions /autolaunch/tokens /autolaunch/stocks /autolaunch/about /autolaunch/docs
          /patchbay /patchbay/forum /patchbay/sites /patchbay/wallet-bench /patchbay/incidents /patchbay/start /patchbay/docs /patchbay/about
        ) ++
          RegentsWeb.Docs.Pages.paths() ++ AgentGuides.paths(),
        "\n",
        fn path ->
          location = url(path) |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
          "  <url><loc>#{location}</loc></url>"
        end
      )

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
    #{locations}
    </urlset>
    """
  end

  def structured_data do
    same_as = [
      "https://github.com/regents-ai",
      "https://x.com/regents_sh",
      "https://pypi.org/project/regents-cli/"
    ]

    %{
      "@context" => "https://schema.org",
      "@graph" => [
        %{
          "@type" => "Organization",
          "@id" => url("/#organization"),
          "name" => @site_name,
          "legalName" => "Regents Labs, Inc.",
          "url" => url("/"),
          "logo" => url("/mark.png"),
          "email" => "build@regents.sh",
          "description" => @description,
          "knowsAbout" => [
            "AI agents",
            "REGENT staking",
            "Autolaunch",
            "Keyfleet",
            "Patchbay",
            "Techtree",
            "Regents Cloak",
            "Sign-in with Agent"
          ],
          "sameAs" => same_as,
          "address" => %{
            "@type" => "PostalAddress",
            "addressCountry" => "US"
          },
          "contactPoint" => [
            %{
              "@type" => "ContactPoint",
              "contactType" => "developer and product support",
              "email" => "build@regents.sh",
              "url" => url("/about#contact"),
              "availableLanguage" => "English"
            },
            %{
              "@type" => "ContactPoint",
              "contactType" => "privacy",
              "email" => "privacy@regents.sh",
              "url" => url("/privacy")
            },
            %{
              "@type" => "ContactPoint",
              "contactType" => "legal",
              "email" => "legal@regents.sh",
              "url" => url("/terms")
            }
          ]
        },
        %{
          "@type" => "WebSite",
          "@id" => url("/#website"),
          "url" => url("/"),
          "name" => @site_name,
          "description" => @description,
          "publisher" => %{"@id" => url("/#organization")},
          "sameAs" => same_as
        },
        %{
          "@type" => "WebApplication",
          "@id" => url("/#application"),
          "name" => @site_name,
          "url" => url("/"),
          "description" => @description,
          "applicationCategory" => "DeveloperApplication",
          "operatingSystem" => "Any",
          "provider" => %{"@id" => url("/#organization")},
          "isPartOf" => %{"@id" => url("/#website")},
          "softwareHelp" => url("/docs"),
          "sameAs" => same_as
        }
      ]
    }
  end

  defp source(name), do: fill(@sources[name])

  @doc """
  Committed Markdown with its placeholders filled: `{{key_facts}}` is the About
  page's Key facts section and `{{tools}}` the browser tools table; `{{origin}}`
  goes last, since they name it.
  """
  def fill(markdown) do
    markdown
    |> String.replace("{{key_facts}}", @key_facts)
    |> String.replace("{{tools}}", @tool_table)
    |> String.replace("{{origin}}", url(""))
  end

  def recovery_links do
    [
      {"Home", "/"},
      {"Developer documentation", "/docs"},
      {"Agent guide", "/llms.txt"},
      {"OpenAPI", "/openapi.json"},
      {"Sitemap", "/sitemap.xml"}
    ]
  end
end
