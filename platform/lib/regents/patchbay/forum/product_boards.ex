defmodule Regents.Patchbay.Forum.ProductBoards do
  @moduledoc """
  First-party Regents product forums under `/patchbay/<slug>`.

  Each product gets a clean, dedicated Patchbay forum address instead of
  sharing the generic `/patchbay/regents.sh` domain page:

    * `/patchbay/cloak` — Cloak macOS app
    * `/patchbay/techtree` — Techtree evals, environments & verification
    * `/patchbay/autolaunch` — Autolaunch offerings, covered calls & Earn
    * `/patchbay/keyfleet` — Keyfleet fleets, rooms, DMs & treasury
    * `/patchbay/siwa` — Sign-In With Agent (ERC-8128 / RFC 9421)
    * `/patchbay/regents` — Regents Labs accounts, unified `/mcp`, CLI & `$REGENT`
  """

  @type topic :: %{slug: String.t(), label: String.t(), tag: String.t() | nil}

  @type t :: %{
          slug: String.t(),
          name: String.t(),
          title: String.t(),
          tagline: String.t(),
          description: String.t(),
          path: String.t(),
          md_path: String.t(),
          product_path: String.t(),
          product_label: String.t(),
          docs_path: String.t(),
          docs_label: String.t(),
          icon: String.t() | nil,
          monogram: String.t(),
          primary_tag: String.t(),
          default_site_url: String.t(),
          default_tags: String.t(),
          match_origins: [String.t()],
          page_pattern: String.t() | nil,
          topics: [topic()],
          known_fix_ids: [String.t()],
          empty_copy: String.t()
        }

  @boards [
    %{
      slug: "cloak",
      name: "Cloak",
      title: "Cloak Forum",
      tagline: "Private AI menu bar app for macOS",
      description:
        "Support, bug reports, and privacy-mode help for the Cloak macOS app: Local (MLX / llama.cpp), NEAR AI Gateway, Token Inference (Venice + Base, Boundless + Tempo), zkAPI Anon Inference, and Local Agent Box.",
      path: "/patchbay/cloak",
      md_path: "/patchbay/cloak.md",
      product_path: "/cloak",
      product_label: "Cloak for Mac",
      docs_path: "/docs/cloak/reference",
      docs_label: "Cloak docs",
      icon: "/images/cloak/icon.png",
      monogram: "CL",
      primary_tag: "cloak",
      default_site_url: "https://regents.sh/cloak",
      default_tags: "cloak, macos",
      match_origins: [],
      page_pattern: "%/cloak%",
      topics: [
        %{slug: "all", label: "All Cloak", tag: nil},
        %{slug: "local", label: "Local (MLX / llama.cpp)", tag: "local"},
        %{slug: "near-ai", label: "NEAR AI Gateway", tag: "near-ai"},
        %{slug: "token-inference", label: "Token Inference", tag: "token-inference"},
        %{slug: "zkapi", label: "zkAPI Anon", tag: "zkapi"},
        %{slug: "agent-box", label: "Agent Box & CloakDoor", tag: "agent-box"}
      ],
      known_fix_ids: ~w(
        hosted-mcp-session
        siwa-headers-missing
        siwa-signature-invalid
      ),
      empty_copy: "No Cloak discussions yet. Ask the first question or report an issue above."
    },
    %{
      slug: "techtree",
      name: "Techtree",
      title: "Techtree Forum",
      tagline: "Skills, evals, environments & verification",
      description:
        "Questions, verification help, and bug reports for Techtree skills, training environments, formal verification, Agent Wallet Bench, and Watchdog security.",
      path: "/patchbay/techtree",
      md_path: "/patchbay/techtree.md",
      product_path: "/techtree/app",
      product_label: "Open Techtree",
      docs_path: "/techtree/docs",
      docs_label: "Techtree docs",
      icon: nil,
      monogram: "TT",
      primary_tag: "techtree",
      default_site_url: "https://regents.sh/techtree",
      default_tags: "techtree",
      match_origins: ["techtree.sh"],
      page_pattern: "%/techtree%",
      topics: [
        %{slug: "all", label: "All Techtree", tag: nil},
        %{slug: "skills", label: "Skills & Evals", tag: "skills"},
        %{slug: "environments", label: "Environments", tag: "environments"},
        %{slug: "formal", label: "Formal Verification", tag: "formal"},
        %{slug: "wallet-bench", label: "Wallet Bench", tag: "wallet-bench"},
        %{slug: "security", label: "Security & Watchdog", tag: "security"}
      ],
      known_fix_ids: ~w(
        siwa-headers-missing
        siwa-signature-invalid
        hosted-mcp-session
      ),
      empty_copy: "No Techtree discussions here yet. Ask a question above."
    },
    %{
      slug: "autolaunch",
      name: "Autolaunch",
      title: "Autolaunch Forum",
      tagline: "Onchain offerings, covered calls & Earn",
      description:
        "Support and troubleshooting for Autolaunch auctions, agent business launches, covered calls, isolated after-hours stocks, and Earn.",
      path: "/patchbay/autolaunch",
      md_path: "/patchbay/autolaunch.md",
      product_path: "/autolaunch/app",
      product_label: "Open Autolaunch",
      docs_path: "/autolaunch/docs",
      docs_label: "Autolaunch docs",
      icon: nil,
      monogram: "AL",
      primary_tag: "autolaunch",
      default_site_url: "https://regents.sh/autolaunch",
      default_tags: "autolaunch",
      match_origins: ["autolaunch.sh"],
      page_pattern: "%/autolaunch%",
      topics: [
        %{slug: "all", label: "All Autolaunch", tag: nil},
        %{slug: "auctions", label: "Auctions", tag: "auctions"},
        %{slug: "covered-calls", label: "Covered Calls", tag: "covered-calls"},
        %{slug: "after-hours", label: "After-Hours Stocks", tag: "after-hours"},
        %{slug: "earn", label: "Earn", tag: "earn"},
        %{slug: "launches", label: "Agent Launches", tag: "launches"}
      ],
      known_fix_ids: ~w(
        siwa-headers-missing
        siwa-signature-invalid
        hosted-mcp-session
      ),
      empty_copy: "No Autolaunch discussions here yet. Ask a question above."
    },
    %{
      slug: "keyfleet",
      name: "Keyfleet",
      title: "Keyfleet Forum",
      tagline: "Fleets, keys, rooms, DMs & treasury",
      description:
        "Support for Keyfleet fleets, key holders, encrypted rooms and DMs, governance proposals, treasury operations, and graph workspaces.",
      path: "/patchbay/keyfleet",
      md_path: "/patchbay/keyfleet.md",
      product_path: "/keyfleet/app",
      product_label: "Open Keyfleet",
      docs_path: "/keyfleet/docs",
      docs_label: "Keyfleet docs",
      icon: nil,
      monogram: "KF",
      primary_tag: "keyfleet",
      default_site_url: "https://regents.sh/keyfleet",
      default_tags: "keyfleet",
      match_origins: ["keyfleet.ai", "keyfleet.sh"],
      page_pattern: "%/keyfleet%",
      topics: [
        %{slug: "all", label: "All Keyfleet", tag: nil},
        %{slug: "fleets", label: "Fleets & Keys", tag: "fleets"},
        %{slug: "rooms", label: "Rooms & DMs", tag: "rooms"},
        %{slug: "treasury", label: "Treasury & Proposals", tag: "treasury"},
        %{slug: "graph", label: "Graph Workspace", tag: "graph"},
        %{slug: "git", label: "Git & Code", tag: "git"}
      ],
      known_fix_ids: ~w(
        siwa-headers-missing
        siwa-signature-invalid
        siwa-request-replayed
      ),
      empty_copy: "No Keyfleet discussions here yet. Ask a question above."
    },
    %{
      slug: "siwa",
      name: "SIWA",
      title: "SIWA Forum",
      tagline: "Sign-In With Agent & HTTP request signing",
      description:
        "Troubleshooting for Sign-In With Agent (SIWA): ERC-8128 / RFC 9421 signed HTTP requests, agent pairing, wallet signers, audience bindings, and replay protection.",
      path: "/patchbay/siwa",
      md_path: "/patchbay/siwa.md",
      product_path: "/siwa",
      product_label: "SIWA overview",
      docs_path: "/pair",
      docs_label: "Pair an agent",
      icon: nil,
      monogram: "SW",
      primary_tag: "siwa",
      default_site_url: "https://regents.sh/siwa",
      default_tags: "siwa",
      match_origins: ["siwa.regents.sh"],
      page_pattern: "%/siwa%",
      topics: [
        %{slug: "all", label: "All SIWA", tag: nil},
        %{slug: "signatures", label: "Signatures & Headers", tag: "signatures"},
        %{slug: "pairing", label: "Agent Pairing", tag: "pairing"},
        %{slug: "replay", label: "Replay & Nonces", tag: "replay"},
        %{slug: "wallets", label: "Wallet Signers", tag: "wallets"}
      ],
      known_fix_ids: ~w(
        siwa-headers-missing
        siwa-signature-invalid
        siwa-body-changed
        siwa-request-replayed
        siwa-signed-for-another-site
        siwa-wallet-audience-disabled
      ),
      empty_copy: "No SIWA discussions here yet. Ask a question above."
    },
    %{
      slug: "regents",
      name: "Regents",
      title: "Regents Forum",
      tagline: "Accounts, unified /mcp, CLI & $REGENT",
      description:
        "Platform-wide support for regents.sh accounts, unified /mcp server, Regents CLI, agent pairing, $REGENT staking, redemption, and site-wide docs.",
      path: "/patchbay/regents",
      md_path: "/patchbay/regents.md",
      product_path: "/",
      product_label: "regents.sh",
      docs_path: "/docs",
      docs_label: "Regents docs",
      icon: nil,
      monogram: "RG",
      primary_tag: "regents",
      default_site_url: "https://regents.sh",
      default_tags: "regents",
      match_origins: ["regents.sh"],
      page_pattern: nil,
      topics: [
        %{slug: "all", label: "All Regents", tag: nil},
        %{slug: "mcp", label: "Unified /mcp", tag: "mcp"},
        %{slug: "cli", label: "Regents CLI", tag: "cli"},
        %{slug: "account", label: "Accounts & Pairing", tag: "account"},
        %{slug: "staking", label: "Staking & Redeem", tag: "staking"},
        %{slug: "docs", label: "Docs & WebMCP", tag: "docs"}
      ],
      known_fix_ids: ~w(
        hosted-mcp-session
        hosted-mcp-internal-error
        no-session-http-write
        siwa-headers-missing
      ),
      empty_copy: "No Regents platform discussions here yet. Ask a question above."
    }
  ]

  @by_slug Map.new(@boards, &{&1.slug, &1})

  @doc "All first-party product forums in display order."
  @spec all() :: [t()]
  def all, do: @boards

  @doc "All first-party product forum slugs."
  @spec slugs() :: [String.t()]
  def slugs, do: Enum.map(@boards, & &1.slug)

  @doc "Looks up a first-party product forum by slug."
  @spec get(String.t()) :: t() | nil
  def get(slug) when is_binary(slug), do: Map.get(@by_slug, slug)
  def get(_other), do: nil

  @doc "Looks up a first-party product forum by slug, raising if unknown."
  @spec fetch!(String.t()) :: t()
  def fetch!(slug), do: Map.fetch!(@by_slug, slug)

  @doc "Returns the feed matching spec consumed by `Regents.Patchbay.Forum.Feed`."
  @spec feed_spec(t()) :: %{
          slug: String.t(),
          tag: String.t(),
          origins: [String.t()],
          page_pattern: String.t() | nil
        }
  def feed_spec(board) do
    %{
      slug: board.slug,
      tag: board.primary_tag,
      origins: board.match_origins,
      page_pattern: board.page_pattern
    }
  end

  @doc "Returns the selected topic entry for `board`, defaulting to `\"all\"`."
  @spec selected_topic(t(), term()) :: topic()
  def selected_topic(board, slug) when is_binary(slug) do
    Enum.find(board.topics, hd(board.topics), &(&1.slug == slug))
  end

  def selected_topic(board, _other), do: hd(board.topics)

  @doc "Prefilled comma-separated tags for new questions opened on `board`."
  @spec prefilled_tags(t(), topic()) :: String.t()
  def prefilled_tags(board, %{tag: nil}), do: board.default_tags

  def prefilled_tags(board, %{tag: topic_tag}) do
    board.default_tags
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Kernel.++([topic_tag])
    |> Enum.uniq()
    |> Enum.join(", ")
  end
end
