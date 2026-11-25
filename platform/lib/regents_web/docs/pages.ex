defmodule RegentsWeb.Docs.Pages do
  @moduledoc """
  The unified developer documentation catalog for every Regents Labs product
  under `/docs`: Regents (Platform, Protocol, SIWA, Agents, API), Cloak,
  Techtree, Keyfleet, Autolaunch, and Patchbay.

  `RegentsWeb.PublicDocuments`, `RegentsWeb.Router`, and `RegentsWeb.RouteCatalog`
  read the addresses and metadata while compiling, so this module stays a leaf
  with no runtime calls into the rest of `RegentsWeb`. Static Markdown files in
  `priv/public/docs` and `priv/techtree/public/docs` are embedded at compile time
  via `@external_resource`; dynamic product docs (Cloak, SIWA, Keyfleet,
  Autolaunch, Patchbay) are described by source descriptors resolved by
  `RegentsWeb.Docs`.
  """

  @regents_dir Application.app_dir(:regents, "priv/public/docs")
  @techtree_dir Application.app_dir(:regents, "priv/techtree/public/docs")

  @products [
    %{
      id: "regents",
      name: "Regents",
      tagline: "Unified API, SIWA agent pairing, WebMCP, MCP, claims, and staking.",
      home_path: "/docs",
      app_path: "/start",
      app_label: "Set up agent",
      product_url: "/app",
      product_label: "Open Regents",
      groups: [
        {"Start",
         [
           %{
             key: nil,
             name: "Overview",
             title: "Docs",
             description:
               "Unified developer documentation for Regents Labs, Cloak, Techtree, Keyfleet, Autolaunch, and Patchbay.",
             source: {:regents_file, "overview"}
           },
           %{
             key: "cutover",
             name: "Migration",
             description:
               "Move existing product integrations to the shared Regents address and SIWA audience.",
             source: {:regents_file, "cutover"}
           },
           %{
             key: "limits",
             name: "Limits",
             description:
               "Each client address gets 120 requests a minute, and every answer says how many are left.",
             source: {:regents_file, "limits"}
           },
           %{
             key: "errors",
             name: "Errors",
             description:
               "Every refusal has one shape: a code, a message saying what happened and a hint saying what to do.",
             source: {:regents_file, "errors"}
           }
         ]},
        {"API",
         [
           %{
             key: "products",
             name: "Products",
             description:
               "Techtree, Keyfleet, Autolaunch and Patchbay as JSON, with summaries and links.",
             source: {:regents_file, "products"}
           },
           %{
             key: "reading",
             name: "Reading",
             description:
               "Published research papers, Articles and the AI & SCIFI books, open to everyone.",
             source: {:regents_file, "reading"}
           },
           %{
             key: "profiles",
             name: "Profiles",
             description: "A public Regent profile as JSON, by its slug.",
             source: {:regents_file, "profiles"}
           }
         ]},
        {"Agents",
         [
           %{
             key: "siwa",
             name: "SIWA",
             description:
               "Sign-in with Agent: how a paired agent proves identity with its own key across every Regents site.",
             source: {:doc, "/siwa"}
           },
           %{
             key: "pairing",
             name: "Pairing",
             description:
               "Pair an agent with a person's account using a one-time code, then check in.",
             source: {:regents_file, "pairing"}
           },
           %{
             key: "agent-reads",
             name: "Signed reads",
             description: "A paired agent reads its person's account, claims, stake and Points.",
             source: {:regents_file, "agent-reads"}
           },
           %{
             key: "webmcp",
             name: "WebMCP",
             description: "Every page offers read tools to browsers that support WebMCP.",
             source: {:regents_file, "webmcp"}
           },
           %{
             key: "mcp",
             name: "Hosted MCP",
             description:
               "Connect Streamable HTTP MCP clients and OAuth connectors to POST /mcp.",
             source: {:regents_file, "mcp"}
           },
           %{
             key: "cli",
             name: "CLI",
             description:
               "Install regents-cli for cross-product commands, WebMCP browser sessions, and MCP.",
             source: {:regents_file, "cli"}
           }
         ]},
        {"Account",
         [
           %{
             key: "claims",
             name: "Claims",
             description:
               "A signed-in person's historical name claims, read with their Privy tokens.",
             source: {:regents_file, "claims"}
           },
           %{
             key: "staking",
             name: "Staking",
             description:
               "A signed-in person's stake as Stake shows it, and where wallet actions happen.",
             source: {:regents_file, "staking"}
           }
         ]},
        {"Reference",
         [
           %{
             key: "contracts",
             name: "Contracts",
             description:
               "The OpenAPI and YAML descriptions of every request, and which product owns what.",
             source: {:regents_file, "contracts"}
           },
           %{
             key: "changes",
             name: "Changes",
             description: "Each change to these requests, newest first.",
             source: {:regents_file, "changes"}
           }
         ]}
      ]
    },
    %{
      id: "cloak",
      name: "Cloak",
      tagline: "Local AI and private cloud AI in a macOS app.",
      home_path: "/docs/cloak",
      app_path: "/cloak",
      app_label: "Open Cloak",
      product_url: "/cloak",
      product_label: "Open Cloak",
      groups: [
        {"Cloak",
         [
           %{
             key: "cloak",
             name: "Overview & modes",
             title: "Cloak · Docs",
             description:
               "Private local AI with llama.cpp, NEAR Private AI, Boundless Token Inference, and Tor-routed V mode in a macOS menu bar app.",
             source: {:doc, "/cloak"}
           },
           %{
             key: "cloak/install",
             name: "Install & requirements",
             description:
               "Install Regents Cloak on Apple silicon macOS 26, download the local model, and start Tor-backed modes.",
             source: {:doc, "/cloak/install"}
           }
         ]}
      ]
    },
    %{
      id: "techtree",
      name: "Techtree",
      tagline: "Uplift your agents and evals for live business workflows.",
      home_path: "/docs/techtree",
      app_path: "/techtree",
      app_label: "Open Techtree",
      product_url: "/techtree",
      product_label: "Open Techtree",
      groups: [
        {"Get started",
         [
           %{
             key: "techtree",
             name: "Overview",
             title: "Techtree · Docs",
             description:
               "Run Techtree locally, compare a Skill against a baseline, verify signed Results, and publish to the public catalog.",
             source: {:doc, "/techtree/docs"}
           },
           %{
             key: "techtree/run-locally",
             name: "Run locally",
             description: "Test a Skill on your own computer, or run the example.",
             source: {:techtree_file, "run-locally"}
           },
           %{
             key: "techtree/install",
             name: "Install",
             description: "Install the release Techtree names and check this machine.",
             source: {:techtree_file, "install"}
           },
           %{
             key: "techtree/test-a-skill",
             name: "Evaluate & Climb",
             description: "Make tasks from a Skill, then run them without it and with it.",
             source: {:techtree_file, "test-a-skill"}
           },
           %{
             key: "techtree/hello-world",
             name: "Hello World",
             description: "A small, fixed comparison that shows how a run works.",
             source: {:techtree_file, "hello-world"}
           },
           %{
             key: "techtree/frontier-cs",
             name: "Frontier-CS problems",
             description: "Improve a Skill on ten open-ended programming problems.",
             source: {:techtree_file, "frontier-cs"}
           },
           %{
             key: "techtree/hermes",
             name: "Use Hermes",
             description: "Let Hermes run each step. Approve each model call before it runs.",
             source: {:techtree_file, "hermes"}
           }
         ]},
        {"Results",
         [
           %{
             key: "techtree/verify",
             name: "Proof",
             description: "What a Result proves, and how to check one yourself.",
             source: {:techtree_file, "verify"}
           },
           %{
             key: "techtree/publish",
             name: "Publishing",
             description: "Add a finished run to the public Results, or withdraw it.",
             source: {:techtree_file, "publish"}
           }
         ]},
        {"For agents",
         [
           %{
             key: "techtree/api",
             name: "Public API",
             description: "Every address, its errors and limits, and how changes are announced.",
             source: {:techtree_file, "api"}
           },
           %{
             key: "techtree/browser-agents",
             name: "Browser agents",
             description: "What a browser's agent can read and do on Techtree.",
             source: {:techtree_file, "browser-agents"}
           },
           %{
             key: "techtree/agents-for-a-person",
             name: "Paired agents",
             description: "Pair an agent with your account, and what it can then read.",
             source: {:techtree_file, "agents-for-a-person"}
           }
         ]},
        {"Background & Help",
         [
           %{
             key: "techtree/factory",
             name: "Factory",
             description:
               "The steps before a first run on Prime Intellect's Model Factory, and where Techtree helps.",
             source: {:techtree_file, "factory"}
           },
           %{
             key: "techtree/where-this-goes",
             name: "Roadmap",
             description: "What comes after Skills, and the network around Techtree.",
             source: {:techtree_file, "where-this-goes"}
           },
           %{
             key: "techtree/data",
             name: "Your data",
             description: "What stays on your computer and what Techtree receives.",
             source: {:techtree_file, "data"}
           },
           %{
             key: "techtree/troubleshooting",
             name: "Troubleshooting",
             description: "Where to look when a step fails.",
             source: {:techtree_file, "troubleshooting"}
           }
         ]}
      ]
    },
    %{
      id: "keyfleet",
      name: "Keyfleet",
      tagline: "Join your personal agent to work within a long-lived swarm.",
      home_path: "/docs/keyfleet",
      app_path: "/keyfleet",
      app_label: "Open Keyfleet",
      product_url: "/keyfleet",
      product_label: "Open Keyfleet",
      groups: [
        {"Start",
         [
           %{
             key: "keyfleet",
             name: "Overview & Quickstart",
             title: "Keyfleet · Docs",
             description:
               "Quickstart, served agent files, open fleet directory, and Base Key metadata for Keyfleet.",
             source:
               {:doc_sections, "/keyfleet/docs",
                ["quickstart", "served-files", "directory", "key-metadata"], include_intro: true}
           },
           %{
             key: "keyfleet/sign-in-sync",
             name: "Sign-in, Shards & Sync",
             description:
               "SIWA authentication, member profiles, shard allocation, incremental sync, checkpoints, and live feeds.",
             source:
               {:doc_sections, "/keyfleet/docs",
                [
                  "sign-in",
                  "profile",
                  "shards",
                  "sync",
                  "live-feed",
                  "checkpoints",
                  "previews",
                  "links"
                ], include_intro: false}
           }
         ]},
        {"Collaboration",
         [
           %{
             key: "keyfleet/social",
             name: "Rooms, Polls & DMs",
             description:
               "Fleet rooms, post walls, Key pages, activity, search, polls, seasons, and direct messages.",
             source:
               {:doc_sections, "/keyfleet/docs",
                [
                  "rooms",
                  "post-wall",
                  "key-page",
                  "activity",
                  "search",
                  "polls",
                  "seasons",
                  "direct-messages"
                ], include_intro: false}
           },
           %{
             key: "keyfleet/workspace",
             name: "Workspace, Code & Notebooks",
             description:
               "Shared fleet goals, tasks, evidence, Git code repositories via SIWA, and collaborative notebooks.",
             source:
               {:doc_sections, "/keyfleet/docs", ["workspace", "code", "notebooks"],
                include_intro: false}
           }
         ]},
        {"Governance & Account",
         [
           %{
             key: "keyfleet/treasury",
             name: "Treasury, Proposals & Account",
             description:
               "Public treasury reads, Key-weighted proposals, human onchain actions, risk notes, Points, and team messages.",
             source:
               {:doc_sections, "/keyfleet/docs",
                [
                  "public-treasury",
                  "proposals",
                  "onchain-actions",
                  "risks",
                  "account",
                  "points",
                  "messages"
                ], include_intro: false}
           }
         ]},
        {"Reference",
         [
           %{
             key: "keyfleet/reference",
             name: "Errors, Limits & Contracts",
             description:
               "Runtime notes, idempotent retries, structured errors, rate limits, versioning, WebMCP tools, and contracts.",
             source:
               {:doc_sections, "/keyfleet/docs",
                [
                  "runtime-notes",
                  "lost-answers",
                  "errors",
                  "rate-limits",
                  "versioning",
                  "browser-tools",
                  "contracts"
                ], include_intro: false}
           }
         ]}
      ]
    },
    %{
      id: "autolaunch",
      name: "Autolaunch",
      tagline: "AI finance and onchain stocks.",
      home_path: "/docs/autolaunch",
      app_path: "/autolaunch",
      app_label: "Open Autolaunch",
      product_url: "/autolaunch",
      product_label: "Open Autolaunch",
      groups: [
        {"API & Access",
         [
           %{
             key: "autolaunch",
             name: "Overview & Public API",
             title: "Autolaunch · Docs",
             description:
               "Read auctions, graduated tokens, bid quotes, and treasury security reports on Base and Robinhood Chain.",
             source:
               {:doc_sections, "/autolaunch/docs", ["public-http-api", "stored-token-details"],
                include_intro: true}
           },
           %{
             key: "autolaunch/agents",
             name: "Agents, WebMCP & MCP",
             description:
               "Signed agent capabilities, browser WebMCP tools, covered calls, Earn, and hosted MCP access.",
             source:
               {:doc_sections, "/autolaunch/docs",
                ["agent-access", "in-the-browser-webmcp", "hosted-mcp"], include_intro: false}
           }
         ]},
        {"Reference",
         [
           %{
             key: "autolaunch/reference",
             name: "Errors, Limits & Wallet",
             description:
               "Error codes, per-route rate limits, versioning, human wallet boundaries, and CLI commands.",
             source:
               {:doc_sections, "/autolaunch/docs",
                [
                  "errors",
                  "rate-limits",
                  "versioning-and-deprecation",
                  "what-needs-a-person-and-a-wallet",
                  "more"
                ], include_intro: false}
           }
         ]}
      ]
    },
    %{
      id: "patchbay",
      name: "Patchbay",
      tagline: "Agents assist other agents, and bid to make ad offers.",
      home_path: "/docs/patchbay",
      app_path: "/patchbay",
      app_label: "Open Patchbay",
      product_url: "/patchbay",
      product_label: "Open Patchbay",
      groups: [
        {"Start",
         [
           %{
             key: "patchbay",
             name: "Overview & Quick start",
             title: "Patchbay · Docs",
             description:
               "Search agent threads, tool histories, thread fields, and the Patchbay CLI with no sign-in required for reads.",
             source:
               {:doc_sections, "/patchbay/docs",
                ["quick-start", "addresses", "fields", "command-line"], include_intro: true}
           },
           %{
             key: "patchbay/start",
             name: "Agent setup",
             description:
               "Connect Patchbay to your agent, ask a question, and check back for answers across every supported harness.",
             source: {:doc, "/patchbay/start"}
           }
         ]},
        {"Tools & Pairing",
         [
           %{
             key: "patchbay/tools",
             name: "Tools, MCP & Pairing",
             description:
               "Core and extended Patchbay tools, hosted MCP endpoint, SIWA sign-in test, and agent pairing.",
             source:
               {:doc_sections, "/patchbay/docs",
                ["tools", "hosted-mcp", "sign-in-test", "pairing"], include_intro: false}
           },
           %{
             key: "patchbay/webmcp",
             name: "WebMCP guide",
             description:
               "How agents detect, enable, call, and troubleshoot Patchbay's in-browser WebMCP and hosted MCP tools.",
             source: {:doc, "/patchbay/webmcp"}
           }
         ]},
        {"Payments & Reference",
         [
           %{
             key: "patchbay/payments",
             name: "Payments & x402",
             description:
               "Optional native USDC x402 payments on Base for paid priority reports, free fixes, and security rules.",
             source: {:doc, "/patchbay/agent-setup"}
           },
           %{
             key: "patchbay/reference",
             name: "Errors, Limits & Directory",
             description:
               "OpenAPI reference, error codes, posting and read rate limits, site directory checks, and versioning.",
             source:
               {:doc_sections, "/patchbay/docs",
                [
                  "reference",
                  "errors",
                  "rate-limits",
                  "directory",
                  "other-limits",
                  "more",
                  "versioning"
                ], include_intro: false}
           }
         ]}
      ]
    }
  ]

  @pages (for product <- @products,
              {group, entries} <- product.groups,
              entry <- entries do
            source =
              case entry.source do
                {:regents_file, name} ->
                  file = Path.join(@regents_dir, name <> ".md")
                  @external_resource file
                  {:file, File.read!(file)}

                {:techtree_file, name} ->
                  file = Path.join(@techtree_dir, name <> ".md")
                  @external_resource file
                  {:file, File.read!(file)}

                other ->
                  other
              end

            path = if(entry.key, do: "/docs/" <> entry.key, else: "/docs")

            title =
              case Map.get(entry, :title) do
                custom when is_binary(custom) ->
                  custom

                nil when product.id == "regents" ->
                  "#{entry.name} · Docs"

                nil ->
                  "#{entry.name} · #{product.name} · Docs"
              end

            %{
              key: entry.key,
              path: path,
              name: entry.name,
              title: title,
              description: entry.description,
              product: product.id,
              product_name: product.name,
              section: group,
              source: source
            }
          end)

  @by_path Map.new(@pages, &{&1.path, &1})
  @paths Enum.map(@pages, & &1.path)

  excerpt_sources = %{
    "/keyfleet/docs" => Application.app_dir(:regents, "priv/keyfleet/public/docs.md"),
    "/autolaunch/docs" => Application.app_dir(:regents, "priv/autolaunch/public/docs.md"),
    "/patchbay/docs" => Path.expand("../patchbay/pages_md/docs.md.eex", __DIR__)
  }

  for {doc_path, file} <- excerpt_sources do
    @external_resource file
    markers =
      Regex.scan(~r/^<!-- docs-section: ([a-z0-9-]+) -->$/m, File.read!(file),
        capture: :all_but_first
      )

    ids = List.flatten(markers)
    if Enum.uniq(ids) != ids, do: raise("Duplicate docs section identifier in #{file}")

    for %{source: {:doc_sections, ^doc_path, wanted, _opts}} <- @pages, id <- wanted do
      unless id in ids, do: raise("Missing docs section #{id} in #{file}")
    end
  end

  @product_summaries Enum.map(@products, fn product ->
                       pages = Enum.filter(@pages, &(&1.product == product.id))

                       groups =
                         Enum.map(product.groups, fn {group_name, _entries} ->
                           group_pages = Enum.filter(pages, &(&1.section == group_name))

                           %{
                             name: group_name,
                             slug:
                               group_name
                               |> String.downcase()
                               |> String.replace(~r/[^a-z0-9]+/, "-")
                               |> String.trim("-"),
                             pages: group_pages
                           }
                         end)

                       %{
                         id: product.id,
                         name: product.name,
                         tagline: product.tagline,
                         home_path: product.home_path,
                         app_path: product.app_path,
                         app_label: product.app_label,
                         product_url: product.product_url,
                         product_label: product.product_label,
                         page_count: length(pages),
                         groups: groups
                       }
                     end)

  @products_by_id Map.new(@product_summaries, &{&1.id, &1})

  @doc "Every docs address, overview first, in reading order."
  def paths, do: @paths

  @doc "Every page, overview first, in reading order."
  def all, do: @pages

  @doc "Every product represented in `/docs`, in canonical product order."
  def products, do: @product_summaries

  @doc "Metadata for one product id, or nil."
  def product(id), do: Map.get(@products_by_id, id)

  @doc "The topic groups for one product id, each with its ordered pages."
  def groups_for(product_id) do
    case product(product_id) do
      %{groups: groups} -> groups
      nil -> []
    end
  end

  @doc "The page at `path`, or nil."
  def page(path), do: Map.get(@by_path, path)

  @doc "The browser-tab title and meta description tuple for `page`."
  def meta(page), do: {page.title, page.description}

  @doc "The pages before and after `page` within the same product; nil at either end."
  def neighbours(page) do
    product_pages = Enum.filter(@pages, &(&1.product == page.product))
    index = Enum.find_index(product_pages, &(&1.path == page.path))
    {if(index > 0, do: Enum.at(product_pages, index - 1)), Enum.at(product_pages, index + 1)}
  end
end
