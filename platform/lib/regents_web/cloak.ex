defmodule RegentsWeb.Cloak do
  @moduledoc """
  Regents Cloak's words, in the order `/cloak` shows them. The page
  (`RegentsWeb.Cloak.CloakLive`) and its Markdown version (`markdown/0`) both
  read them from here.
  """
  use Boundary, deps: [RegentsWeb], exports: [CloakLive]

  # The heading's two lines (the second is set smaller) and the subtitle: change their words here.
  # The subtitle's first sentence is also the page's description in `RegentsWeb.PublicDocuments`;
  # change it there too.
  @heading [
    "Your agents want privacy.",
    "Local offline AI is good now."
  ]
  @subtitle "Cloak is a tiny menu bar app for your local or private cloud AI. Inspired by Vitalik's anon 'paranoid mode' way to use agents."

  @hero_compact [
    {:text,
     "Cloak is a tiny menu bar app for your local or private cloud AI. Inspired by Vitalik's anon "},
    {:link, "'paranoid mode'", "https://x.com/VitalikButerin/status/2111046730959433793"},
    {:text, " way to use agents."}
  ]

  @pill "MacOS app. Local models. Private cloud AI aggregator."

  @watch_label "Watch the intro"
  @watch_time "0:35"
  @forum_label "Cloak Forum"
  @forum_path "/patchbay/cloak"
  @film "/images/cloak/intro.mp4"
  @releases_url "https://github.com/regents-ai/cloak/releases"
  @download_page_path "/cloak/download/mac"
  @download_url "https://github.com/regents-ai/cloak/releases/download/0.2.2-298/Regents-Cloak-0.2.2-298.dmg"
  @source_url "https://github.com/regents-ai/cloak"
  @docs_path "/docs/cloak/reference"
  @facts "v0.2.2 Beta · Apple silicon · macOS 26+ · Open-source (MIT)"

  @menubar_callouts [
    %{
      n: 1,
      title: "Open chat",
      body:
        "Chat offline on Apple silicon, verify hardware TEEs, or route prompts through local rewriting, Tor, and one-time crypto payments."
    },
    %{
      n: 2,
      title: "A private local API",
      body:
        "Your apps connect at 127.0.0.1:8742/v1. It speaks the OpenAI API, rewrites user prompts locally, and routes over Tor."
    },
    %{
      n: 3,
      title: "3 modes, one menu bar",
      body:
        "Switch between Local AI, Private Cloud Inference (NEAR, Venice, Boundless, zkAPI), and Inference Serving with EigenLayer's Darkbloom."
    }
  ]

  @menubar_modes [
    %{name: "Local AI", tag: "MLX", meta: "Inkling 2 Mini · 10.2 GB", badge: "Offline"},
    %{
      name: "Private Cloud",
      tag: "TEE · Tor",
      meta: "NEAR · Venice · Boundless · zkAPI",
      badge: "4 rails"
    },
    %{
      name: "Inference Serving",
      tag: "macOS 27+",
      meta: "EigenLayer's Darkbloom",
      badge: "Earn"
    }
  ]

  @boundaries [
    %{
      icon: "rewrite",
      title: "Local prompt rewriter",
      detail: "Strips writing style via Qwen 3.5 9B; fails closed on error",
      status: "Auto"
    },
    %{
      icon: "vm",
      title: "NIC-less Linux microVM",
      detail: "Zero virtual network interfaces; exits only via Tor vsock",
      status: "Isolated"
    },
    %{
      icon: "tee",
      title: "Hardware TEE verifier",
      detail: "Checks Intel TDX quotes & NVIDIA verdicts before E2EE v2",
      status: "Pinned"
    },
    %{
      icon: "tor",
      title: "Per-chat Tor circuits",
      detail: "Dedicated IsolateSOCKSAuth circuit + optional live cover traffic",
      status: "Auto"
    },
    %{
      icon: "keychain",
      title: "6 isolated Keychain vaults",
      detail: "Device-only keys per wallet; never synced to iCloud",
      status: "Local"
    }
  ]

  @mode_cards [
    %{
      id: "local",
      ram: "16 GB Mac or more · Offline",
      name: "Local AI",
      body:
        "Local, offline models just had an upgrade: your MacBook can run Inkling 2 Mini on Apple MLX at 56–64 tok/s (outperforming GPT-5) or Metal llama.cpp with offline Local Access for PDFs, OCR, and approved folders. Free, no account.",
      credit: [
        {:text, "Powered by "},
        {:link, "Thinking Machines", "https://thinkingmachines.ai"},
        {:text, " · "},
        {:link, "BenchLM vs GPT-5", "https://benchlm.ai/compare/gpt-5-vs-inkling-2-mini"}
      ]
    },
    %{
      id: "private-cloud",
      ram: "8 GB+ Mac · Hardware TEE, Tor & crypto",
      name: "Private Cloud Inference",
      body:
        "Private cloud LLMs are the safer way to use AI — Cloak aggregates 4 of them per thread: hardware-verified NEAR AI Cloud (0 GB download), Venice AI (Base USDC x402), Boundless (Tempo USDC.e), and zkAPI (fresh one-time key per turn from an ETH deposit) with local rewriting and Tor.",
      credit: [
        {:link, "NEAR", "https://cloud.near.ai"},
        {:text, " · "},
        {:link, "Venice", "https://venice.ai"},
        {:text, " · "},
        {:link, "Boundless", "https://boundless.network"},
        {:text, " · "},
        {:link, "zkAPI", "https://x.com/VitalikButerin/status/2111046730959433793"}
      ]
    },
    %{
      id: "serving",
      ram: "macOS 27+ · Apple silicon",
      name: "Inference Serving",
      body:
        "Serve local models for your own apps or earn payouts on idle Apple silicon memory with EigenLayer's Darkbloom, pausing automatically while you work.",
      credit: [
        {:text, "Powered by "},
        {:link, "EigenLayer", "https://eigenlayer.xyz"},
        {:text, "'s "},
        {:link, "Darkbloom", "https://darkbloom.dev"}
      ]
    }
  ]

  @api_bullets [
    "Localhost-only http://127.0.0.1:8742/v1 with per-app bearer keys",
    "Rewrites user text only — code, tools, and system prompts pass unchanged",
    "Paid automatically via zkAPI with a fresh one-time key per request",
    "Built-in Pi coding agent inside an ephemeral, NIC-less Linux microVM",
    "Native cloak CLI plus progressive Offline Data packs (Kiwix, DevDocs, PubMed)"
  ]

  @curl_example """
                curl http://127.0.0.1:8742/v1/chat/completions \\
                  -H "Authorization: Bearer cloak-..." \\
                  -H "Content-Type: application/json" \\
                  -d '{
                    "model": "auto",
                    "messages": [{"role": "user", "content": "Review PR #418."}]
                  }'
                """
                |> String.trim()

  @ecosystem_heading "One app to aggregate best-in-class local models, cryptographic AI privacy in the cloud, and inference serving"
  @ecosystem [
    %{
      id: "thinking-machines",
      mode: "Local AI",
      note: "Inkling 2 Mini",
      partners: [
        %{
          id: "thinking-machines",
          name: "Thinking Machines",
          href: "https://thinkingmachines.ai",
          wordmark: true
        }
      ]
    },
    %{
      id: "near",
      mode: "Private Cloud",
      note: "Hardware TEE",
      partners: [
        %{id: "near", name: "NEAR AI", href: "https://cloud.near.ai"}
      ]
    },
    %{
      id: "venice-base",
      mode: "Private Cloud",
      note: "Base USDC · x402",
      partners: [
        %{id: "venice", name: "Venice", href: "https://venice.ai"},
        %{id: "base", name: "Base", href: "https://base.org"}
      ]
    },
    %{
      id: "boundless-tempo",
      mode: "Private Cloud",
      note: "Tempo USDC.e · MPP",
      partners: [
        %{id: "boundless", name: "Boundless", href: "https://boundless.network"},
        %{id: "tempo", name: "Tempo", href: "https://tempo.xyz"}
      ]
    },
    %{
      id: "ethereum",
      mode: "Private Cloud",
      note: "zkAPI · ETH",
      partners: [
        %{id: "ethereum", name: "Ethereum", href: "https://ethereum.org"}
      ]
    },
    %{
      id: "eigenlayer",
      mode: "Serving",
      note: "Darkbloom",
      partners: [
        %{id: "eigenlayer", name: "EigenLayer", href: "https://eigenlayer.xyz"}
      ]
    }
  ]

  @agent %{
    title: "Agent Sandbox & Connected Apps",
    summary:
      "Run Cloak's Pi coding agent inside a throwaway Linux microVM with no Mac file access, or connect Cursor, Cline, and Aider through CloakDoor at http://127.0.0.1:8742/v1.",
    bullets: [
      "Isolated VM: shell and file tools stay inside an ephemeral arm64 Linux microVM, never on macOS.",
      "Tor-only egress: agent web calls go over Tor; model calls rewrite locally and pay via zkAPI or Tempo.",
      "External apps: CloakDoor rewrites user text only — code and tool results pass through unchanged."
    ],
    docs_label: "Read the docs",
    docs_href: "/docs/cloak/reference"
  }

  @modes_title "3 modes"

  # Three top-level modes: Local AI, Private Cloud Inference (NEAR, Venice,
  # Boundless, zkAPI), and Inference Serving with EigenLayer's Darkbloom.
  @modes [
    {"Local AI", nil,
     "Runs offline on your Mac with Apple MLX (Inkling 2 Mini) or llama.cpp and offline Local Access — no account, no fees."},
    {"Private Cloud Inference",
     [
       {:text, "Includes "},
       {:link, "NEAR AI Cloud", "https://cloud.near.ai"},
       {:text, ", "},
       {:link, "Venice AI", "https://venice.ai"},
       {:text, ", "},
       {:link, "Boundless", "https://boundless.network"},
       {:text, ", and "},
       {:link, "zkAPI", "https://x.com/VitalikButerin/status/2111046730959433793"},
       {:text, "."}
     ],
     "Pick your cloud privacy rail per thread: hardware-verified Intel TDX + NVIDIA TEEs on NEAR, or local Qwen 3.5 9B prompt rewriting + per-chat Tor over Venice (Base USDC), Boundless (Tempo USDC.e), or zkAPI (fresh one-time key per turn from an ETH deposit)."},
    {"Inference Serving",
     [
       {:text, "Powered by "},
       {:link, "EigenLayer", "https://eigenlayer.xyz"},
       {:text, "'s "},
       {:link, "Darkbloom", "https://darkbloom.dev"},
       {:text, "."}
     ],
     "Serve local models on Apple silicon for your own Mac apps or earn payouts on the Darkbloom network while idle (macOS 27+)."}
  ]

  # The drawn chat window: a synthetic Original -> Sent exchange that shows both
  # what local rephrasing changes (style and irrelevant framing) and what it
  # intentionally keeps (necessary identifiers such as PR #418).
  @window %{
    title: "Chat",
    mode: "zkAPI Anon Inference",
    mode_note: "Local rewrite · Tor · One-time zkAPI key",
    original_label: "Original (stays on your Mac)",
    original:
      "Ugh, totally fried after my train into Zurich—can you draft a short note pushing my 3pm review on PR #418 to Thursday?",
    sent_label: "Sent to model",
    sent:
      "Draft a brief message requesting to reschedule the 3:00 PM review of PR #418 to Thursday.",
    answered:
      "Hi — could we move the 3:00 PM review of PR #418 to Thursday? Let me know what time works best.",
    field: "Message",
    switch: ["Local", "NEAR AI Gateway", "Token Inference", "zkAPI Anon Inference", "Agent"],
    hint: "Rephrased locally; identifiers like PR #418 stay intact."
  }

  @hardware "Apple silicon Mac, macOS 26+. NEAR AI Gateway: 8 GB RAM (0 GB download). Local MLX (10.21 GB) and Tor modes (5.69 GB rewriter): 16 GB RAM."
  @needs "Apple silicon Mac, macOS 26+ (macOS 27+ for Darkbloom serving). NEAR AI Gateway needs 8 GB RAM; Local MLX (10.21 GB) and Tor/rewriter modes (5.69 GB) need 16 GB."

  @mode_access %{
    "Local AI" => "Free local model (10.21 GB MLX)",
    "Private Cloud Inference" =>
      "NEAR API key (0 GB download), Boundless Tempo USDC.e, Venice Base USDC / key, or zkAPI ETH deposit",
    "Inference Serving" =>
      "macOS 27+ · EigenLayer's Darkbloom (Off / Local Only / Network + Local)"
  }
  @caution "Beta software — not independently audited. Keep wallet balances small, back up keys before wiping your Mac (no iCloud sync), and note the 30-day limit on untouched zkAPI deposits."
  @feedback %{
    before: "Questions or bug reports? Post on ",
    link: "regents.sh/patchbay/cloak",
    href: "https://regents.sh/patchbay/cloak",
    github_middle: ", open an issue on ",
    github_link: "GitHub",
    github_href: "https://github.com/regents-ai/cloak",
    middle: ", or follow ",
    social_link: "@regents_sh",
    social_href: "https://x.com/regents_sh",
    after: " on X."
  }

  # Expandable reference notes on `/cloak` written for agents reading the page
  # (Decision 391 c: kept beside the drawn Mac app chat illustration).
  @agent_docs_title "Docs for agents"
  @agent_docs_intro "Structured reference for AI agents."
  @agent_docs [
    %{
      id: "runtime-boundary",
      summary: "Runtime boundary: macOS desktop app (no live web chat)",
      body:
        "Cloak is a native macOS app for Apple silicon; this page is product documentation, not a live chat endpoint. Local Mode runs offline via Apple MLX (Inkling 2 Mini) or llama.cpp after weights download. Threads lock to their mode on turn 1, and opt-in Local Access context stays offline in Local Mode."
    },
    %{
      id: "modes-and-payments",
      summary: "3 modes: Local AI, Private Cloud Inference, and Inference Serving",
      body:
        "1) Local AI: Apple MLX (Inkling 2 Mini, 10.21 GB) or llama.cpp GGUF, free and offline with Local Access. 2) Private Cloud Inference: includes NEAR AI Gateway (Intel TDX + NVIDIA GPU TEE, E2EE v2, 0 GB download), Venice AI (Base USDC x402 or API key), Boundless (Tempo USDC.e MPP), and zkAPI (local Qwen 3.5 9B rewrite + Tor + fresh one-time key per turn from a reusable ETH deposit). 3) Inference Serving: serve local models on Apple silicon or earn payouts with EigenLayer's Darkbloom while idle (macOS 27+). Also includes the sandboxed Pi agent microVM, CloakDoor (http://127.0.0.1:8742/v1), and Offline Data packs."
    },
    %{
      id: "requirements-and-install",
      summary: "Requirements and downloads",
      body:
        "Apple silicon Mac, macOS 26+ (macOS 27+ for Darkbloom serving). 8 GB+ RAM for NEAR AI Gateway (0 GB download); 16 GB+ RAM for Local MLX (10.21 GB) and Tor/rewriter modes (5.69 GB Qwen 3.5 9B). Signed, notarized DMGs (Team 367G3Z7G3J), Sparkle appcast.xml, and SHA-256 checksums are published directly on https://github.com/regents-ai/cloak/releases."
    },
    %{
      id: "agent-discovery",
      summary: "Markdown output and bug reports",
      body:
        "Request /cloak, /cloak/install, /docs/cloak, or /docs/cloak/reference with Accept: text/markdown. Read /llms.txt and /agents.md (or /mcp) for site-wide tools. Report bugs at https://regents.sh/patchbay/cloak, https://github.com/regents-ai/cloak, or build@regents.sh."
    }
  ]

  # The install page, at `/cloak/install`: what to do with the app's file once a
  # person has it. Each step: its one-word title and its sentence.
  @install_path "/cloak/install"
  @install_heading "Install Cloak"
  @install_steps [
    {"Download",
     "Get the signed Regents-Cloak-0.2.2-298.dmg from /cloak/download/mac or GitHub Releases."},
    {"Drag", "Open Regents-Cloak-0.2.2-298.dmg and drag Cloak into Applications."},
    {"Open", "Launch Cloak from Applications. Builds are signed and notarized by Apple."},
    {"Choose",
     "Pick Local (10.21 GB MLX on 16 GB+ Macs) or NEAR AI Gateway (0 GB download on 8 GB+ Macs). Tor modes download the 5.69 GB Qwen 3.5 9B rewriter."},
    {"Start",
     "Local and direct NEAR AI Gateway work immediately. Press Start in the menu bar for Tor, Token Inference, zkAPI, Connected Apps, or the Pi agent."}
  ]
  @updates "Signed Sparkle updates are available on demand or automatically when enabled in Settings."

  # Official release checksums published alongside every signed build in
  # regents-ai/cloak Releases (`SHA256SUMS.txt` and `checksums.json`). Update
  # these values whenever a new release is published by `app/publish.sh`.
  @release_checksums %{
    tag: "0.2.2-298",
    dmg_filename: "Regents-Cloak-0.2.2-298.dmg",
    dmg_sha256: "332a97688cd5fcc971c4c4aeeac9b1924ec38144e9ad9da8713c5a9af5cd889a",
    # Populated on releases published by the updated app/release.sh + app/publish.sh
    # (e.g. {"Installed app binary SHA-256 (Cloak.app/Contents/MacOS/RegentsCloak)", "..."},
    # {"Apple Code Signature CDHash", "..."}).
    extra_hashes: [
      {"Installed app binary SHA-256 (Cloak.app/Contents/MacOS/RegentsCloak)",
       "7f378d5635e1a4f0e4e78720bd0cb7ad653db9a571319ee135cc2d7edbcccc01"},
      {"Apple Code Signature CDHash", "4d6b278037a367548ef47f0ec1077c801e7f3dd4"}
    ],
    team_id: "367G3Z7G3J",
    release_url: "https://github.com/regents-ai/cloak/releases/latest",
    sums_url: "https://github.com/regents-ai/cloak/releases/latest/download/SHA256SUMS.txt",
    commands: [
      {"Verify DMG SHA-256", "shasum -a 256 ~/Downloads/Regents-Cloak-0.2.2-298.dmg"},
      {"Verify app binary SHA-256",
       "shasum -a 256 \"/Applications/Cloak.app/Contents/MacOS/RegentsCloak\""},
      {"Verify Apple signature (Team 367G3Z7G3J)",
       "codesign -dvv --strict \"/Applications/Cloak.app\""},
      {"Verify Apple notarization",
       "spctl --assess --type execute -vv \"/Applications/Cloak.app\""}
    ]
  }

  @github_api_url "https://api.github.com/repos/regents-ai/cloak"
  @github_stars_ttl_ms :timer.minutes(10)
  @github_stars_throttle_ms :timer.seconds(30)
  @github_stars_cache_key {__MODULE__, :github_stars}
  @github_stars_refresh_key {__MODULE__, :github_stars_refresh_at}

  def github_stars do
    now = System.monotonic_time(:millisecond)

    case :persistent_term.get(@github_stars_cache_key, nil) do
      {count, fetched_at} when is_integer(count) and now - fetched_at < @github_stars_ttl_ms ->
        count

      {count, _fetched_at} when is_integer(count) ->
        refresh_github_stars_async()
        count

      _ ->
        refresh_github_stars_async()
        0
    end
  end

  def github_stars_fresh? do
    now = System.monotonic_time(:millisecond)

    case :persistent_term.get(@github_stars_cache_key, nil) do
      {count, fetched_at} when is_integer(count) and now - fetched_at < @github_stars_ttl_ms ->
        true

      _ ->
        false
    end
  end

  def refresh_github_stars do
    now = System.monotonic_time(:millisecond)
    :persistent_term.put(@github_stars_refresh_key, now)

    case fetch_github_stars() do
      {:ok, count} ->
        :persistent_term.put(
          @github_stars_cache_key,
          {count, System.monotonic_time(:millisecond)}
        )

        {:ok, count}

      :error ->
        :error
    end
  end

  def format_star_count(count) when is_integer(count) and count >= 1_000 do
    (count / 1_000)
    |> :erlang.float_to_binary(decimals: 1)
    |> String.trim_trailing(".0")
    |> Kernel.<>("k")
  end

  def format_star_count(count) when is_integer(count) and count >= 0, do: Integer.to_string(count)
  def format_star_count(_), do: "0"

  defp refresh_github_stars_async do
    now = System.monotonic_time(:millisecond)
    last_attempt = :persistent_term.get(@github_stars_refresh_key, nil)

    if is_nil(last_attempt) or now - last_attempt >= @github_stars_throttle_ms do
      :persistent_term.put(@github_stars_refresh_key, now)

      Task.start(fn ->
        refresh_github_stars()
      end)
    end

    :ok
  end

  defp fetch_github_stars do
    case Req.get(@github_api_url,
           headers: [
             {"user-agent", "regents-sh"},
             {"accept", "application/vnd.github+json"}
           ],
           connect_options: [timeout: 2_000],
           receive_timeout: 3_000,
           retry: false
         ) do
      {:ok, %{status: 200, body: %{"stargazers_count" => count}}} when is_integer(count) ->
        {:ok, count}

      _ ->
        :error
    end
  rescue
    _ -> :error
  end

  def heading, do: @heading
  def subtitle, do: @subtitle
  def hero_compact, do: @hero_compact
  def pill, do: @pill
  def watch_label, do: @watch_label
  def watch_time, do: @watch_time
  def forum_label, do: @forum_label
  def forum_path, do: @forum_path
  def film, do: @film
  def releases_url, do: @releases_url
  def download_page_path, do: @download_page_path
  def download_url, do: @download_url
  def source_url, do: @source_url
  def docs_path, do: @docs_path
  def menubar_callouts, do: @menubar_callouts
  def menubar_modes, do: @menubar_modes
  def boundaries, do: @boundaries
  def mode_cards, do: @mode_cards
  def api_bullets, do: @api_bullets
  def curl_example, do: @curl_example
  def agent, do: @agent
  def facts, do: @facts
  def ecosystem_heading, do: @ecosystem_heading
  def ecosystem, do: @ecosystem
  def modes_title, do: @modes_title
  def modes, do: @modes
  def window, do: @window
  def needs, do: @needs
  def caution, do: @caution
  def feedback, do: @feedback
  def agent_docs_title, do: @agent_docs_title
  def agent_docs_intro, do: @agent_docs_intro
  def agent_docs, do: @agent_docs
  def install_path, do: @install_path
  def install_heading, do: @install_heading
  def install_steps, do: @install_steps
  def updates, do: @updates
  def release_checksums, do: @release_checksums

  @doc "The page as Markdown, what `/cloak` answers when Markdown is asked for."
  def markdown do
    modes =
      Enum.map_join(@modes, "\n", fn
        {name, nil, sentence} ->
          "| #{name} | #{sentence} | #{@mode_access[name]} |"

        {name, credit_parts, sentence} ->
          credit_md =
            Enum.map_join(credit_parts, "", fn
              {:text, text} -> text
              {:link, label, href} -> "[#{label}](#{href})"
            end)

          "| #{name} | #{String.trim_trailing(sentence, ".")}. #{credit_md} | #{@mode_access[name]} |"
      end)

    ecosystem =
      Enum.map_join(@ecosystem, "\n", fn group ->
        names = Enum.map_join(group.partners, " + ", &"[#{&1.name}](#{&1.href})")
        "- #{names} — #{group.note}"
      end)

    agent_docs =
      Enum.map_join(@agent_docs, "\n\n", fn doc ->
        "### #{doc.summary}\n\n#{doc.body}"
      end)

    film = RegentsWeb.Endpoint.static_url() <> RegentsWeb.Endpoint.static_path(@film)

    """
    #{@pill}

    # #{Enum.join(@heading, " ")}

    Cloak is a tiny menu bar app for your local or private cloud AI. Inspired by Vitalik's anon ['paranoid mode'](https://x.com/VitalikButerin/status/2111046730959433793) way to use agents.

    - Local, offline models just had an upgrade. Your MacBook can run Inkling 2 Mini and it [is better](https://benchlm.ai/compare/gpt-5-vs-inkling-2-mini) than GPT-5.
    - Private cloud LLMs are the safer way to use AI. Cloak aggregates 4 of them. Using it is a hedge against a more-dangerous future: your personal and business info is being tracked and logged, and the future usage of your most important personal information is unknown and historically dangerous for some groups of people.

    - [Download for Mac (Regents-Cloak-0.2.2-298.dmg)](#{@download_url})
    - [#{@watch_label} (#{@watch_time})](#{film})
    - [Install & checksums](#{RegentsWeb.PublicDocuments.url(@install_path)})
    - [View releases](#{@releases_url})
    - [Read docs](#{RegentsWeb.PublicDocuments.url(@docs_path)})
    - [#{@forum_label}](#{RegentsWeb.PublicDocuments.url(@forum_path)})
    - [View source](#{@source_url})

    #{@facts}

    ## #{@ecosystem_heading}

    #{ecosystem}

    ## #{@modes_title}

    | Mode | Where the prompt is handled | What you need |
    | --- | --- | --- |
    #{modes}

    ## #{@agent.title}

    #{@agent.summary}

    #{Enum.map_join(@agent.bullets, "\n", &"- #{&1}")}

    [#{@agent.docs_label}](#{RegentsWeb.PublicDocuments.url(@docs_path)})

    ## Example: Original → Sent

    - **#{@window.original_label}:** #{@window.original}
    - **#{@window.sent_label} (#{@window.mode} — #{@window.mode_note}):** #{@window.sent}
    - **Answer:** #{@window.answered}

    #{@window.hint}

    ## #{@agent_docs_title}

    #{@agent_docs_intro}

    #{agent_docs}

    ## Verify your download

    - **Latest published release:** `#{@release_checksums.tag}` ([GitHub Releases](#{@release_checksums.release_url}) · [SHA256SUMS.txt](#{@release_checksums.sums_url}))
    - **DMG (`#{@release_checksums.dmg_filename}` / `Regents-Cloak.dmg`) SHA-256:** `#{@release_checksums.dmg_sha256}`
    - **Apple Developer ID Team:** `#{@release_checksums.team_id}`
    - Full macOS verification commands (`shasum`, `codesign`, `spctl`) are listed on [Install & requirements](#{RegentsWeb.PublicDocuments.url(@install_path <> "#verify-your-download")}) and live inside Cloak's **Settings → Status** pane.

    ## Needs

    #{@hardware}

    Darkbloom Serving requires macOS 27+. See [Wallet security & recovery](#{RegentsWeb.PublicDocuments.url("/docs/cloak/wallets")}) before funding a wallet.

    ## Caution

    #{@caution}

    #{@feedback.before}[#{@feedback.link}](#{@feedback.href})#{@feedback.github_middle}[#{@feedback.github_link}](#{@feedback.github_href})#{@feedback.middle}[#{@feedback.social_link}](#{@feedback.social_href})#{@feedback.after}
    """
  end

  @doc "The install page as Markdown, what `/cloak/install` answers when Markdown is asked for."
  def install_markdown do
    steps =
      @install_steps
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {{title, sentence}, n} -> "#{n}. **#{title}.** #{sentence}" end)

    checksums = release_checksums()

    extra_lines =
      Enum.map(checksums.extra_hashes, fn {label, value} -> "- **#{label}:** `#{value}`" end)

    verify_lines =
      ([
         "- **Latest published release:** `#{checksums.tag}` ([GitHub Releases](#{checksums.release_url}) · [SHA256SUMS.txt](#{checksums.sums_url}))",
         "- **DMG (`#{checksums.dmg_filename}` / `Regents-Cloak.dmg`) SHA-256:** `#{checksums.dmg_sha256}`"
       ] ++
         extra_lines ++
         ["- **Apple Developer ID Team:** `#{checksums.team_id}`"])
      |> Enum.join("\n")

    commands =
      Enum.map_join(checksums.commands, "\n\n", fn {label, cmd} ->
        "# #{label}\n#{cmd}"
      end)

    """
    # #{@install_heading}

    #{@facts}

    - [View releases](#{@releases_url})
    - [View source](#{@source_url})

    #{steps}

    ## Verify your download

    Compare checksums across three independent places — this page, [GitHub Releases](#{@release_checksums.release_url}), and Cloak's **Settings → Status** pane — using macOS's built-in Terminal tools:

    #{verify_lines}

    ```sh
    #{commands}
    ```

    ## Updates

    #{@updates}

    ## Caution

    #{@caution}

    #{@feedback.before}[#{@feedback.link}](#{@feedback.href})#{@feedback.github_middle}[#{@feedback.github_link}](#{@feedback.github_href})#{@feedback.middle}[#{@feedback.social_link}](#{@feedback.social_href})#{@feedback.after}
    """
  end
end
