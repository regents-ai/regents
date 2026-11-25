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
    "Choose what leaves your Mac.",
    "Run locally, or pick your privacy in the cloud."
  ]
  @subtitle "Chat offline on Apple silicon, or route cloud prompts through TEEs, local rewriting, Tor, and one-time crypto payments."

  @pill "Simple Local AI. Private Cloud AI Aggregator."

  @watch_label "Watch the intro"
  @watch_time "0:20"
  @forum_label "Cloak Forum"
  @forum_path "/patchbay/cloak"
  @film "/images/cloak/intro.mp4"
  @releases_url "https://github.com/regents-ai/cloak-releases/releases"
  @source_url "https://github.com/regents-ai/cloak"
  @docs_path "/docs/cloak/reference"
  @facts "v0.2.0 Beta · Apple silicon · macOS 26+ · Unaudited beta — keep wallet balances small."

  @ecosystem_heading "One app to aggregate best-in-class local models, cryptographic AI privacy in the cloud, and inference serving"
  @ecosystem [
    %{
      id: "thinking-machines",
      note: "Local models · Inkling 2 Mini",
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
      id: "boundless-tempo",
      note: "Tempo USDC.e · MPP",
      partners: [
        %{id: "boundless", name: "Boundless", href: "https://boundless.network"},
        %{id: "tempo", name: "Tempo", href: "https://tempo.xyz"}
      ]
    },
    %{
      id: "venice-base",
      note: "Base USDC · x402",
      partners: [
        %{id: "venice", name: "Venice", href: "https://venice.ai"},
        %{id: "base", name: "Base", href: "https://base.org"}
      ]
    },
    %{
      id: "ethereum",
      note: "zkAPI · ETH",
      partners: [
        %{id: "ethereum", name: "Ethereum", href: "https://ethereum.org"}
      ]
    },
    %{
      id: "eigenlayer",
      note: "Darkbloom serving",
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

  @modes_title "5 modes"

  # Each mode, in the order a new user decides: local first, then each remote
  # option and local/network serving.
  @modes [
    {"Local", nil,
     "Runs on your Mac with Apple MLX (Inkling 2 Mini) or llama.cpp. Offline after download — no account, no fees."},
    {"NEAR AI Gateway",
     [
       {:text, "Hardware-verified on "},
       {:link, "NEAR AI Cloud", "https://cloud.near.ai"},
       {:text, "."}
     ],
     "Verifies Intel TDX and NVIDIA GPU attestation before encrypting prompts end-to-end. Uses your NEAR key; Tor and trace exports are optional."},
    {"Token Inference",
     [
       {:text, "Served by "},
       {:link, "Venice AI", "https://venice.ai"},
       {:text, " or "},
       {:link, "Boundless", "https://boundless.network"},
       {:text, "."}
     ],
     "Rewrites prompts locally and routes over Tor. Pay per call with Tempo USDC.e via Boundless, or Base USDC (x402) / a Venice API key."},
    {"zkAPI Anon Inference",
     [
       {:text, "Inspired by Vitalik's "},
       {:link, "X post", "https://x.com/VitalikButerin/status/2111046730959433793"},
       {:text, "."}
     ],
     "Local rewrite, Tor, optional cover traffic, and a fresh one-time zkAPI key per turn from an ETH deposit — no reusable wallet or key."},
    {"Darkbloom Serving",
     [
       {:text, "Powered by "},
       {:link, "Darkbloom", "https://darkbloom.dev"},
       {:text, " and "},
       {:link, "EigenLayer", "https://eigenlayer.xyz"},
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
    "Local" => "Free local model (10.21 GB MLX)",
    "NEAR AI Gateway" => "NEAR AI Cloud key",
    "Token Inference" => "Tempo USDC.e (Boundless MPP), Base USDC (Venice x402), or Venice key",
    "zkAPI Anon Inference" => "ETH deposit on Ethereum Mainnet (30-day limit)",
    "Darkbloom Serving" => "macOS 27+ (Off / Local Only / Network + Local)"
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
      summary: "Modes, routing, and payments",
      body:
        "1) Local: Apple MLX (Inkling 2 Mini, 10.21 GB) or llama.cpp GGUF, free and offline. 2) NEAR AI Gateway: verifies Intel TDX + NVIDIA GPU attestation before E2EE v2 to NEAR AI Cloud (Qwen3.8-27B); optional Tor and local trace export. 3) Token Inference: local Qwen 3.5 9B rewrite + Tor; Boundless (Tempo USDC.e MPP) or Venice AI (Base USDC x402 or API key). 4) zkAPI Anon Inference: local rewrite + Tor + optional cover traffic + one-time zkAPI key from an Ethereum Mainnet ETH deposit. 5) Darkbloom Serving: serve local models on Apple silicon for your own apps or earn payouts on Darkbloom / EigenLayer while idle (macOS 27+). Also includes the sandboxed Pi agent microVM, CloakDoor (http://127.0.0.1:8742/v1), and Offline Data packs."
    },
    %{
      id: "requirements-and-install",
      summary: "Requirements and downloads",
      body:
        "Apple silicon Mac, macOS 26+ (macOS 27+ for Darkbloom serving). 8 GB+ RAM for NEAR AI Gateway (0 GB download); 16 GB+ RAM for Local MLX (10.21 GB) and Tor/rewriter modes (5.69 GB Qwen 3.5 9B). Signed, notarized DMGs (Team 367G3Z7G3J) and SHA-256 checksums live at https://github.com/regents-ai/cloak-releases/releases; source at https://github.com/regents-ai/cloak."
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
    {"Download", "Get the signed Regents-Cloak.dmg from GitHub Releases."},
    {"Drag", "Open Regents-Cloak.dmg and drag Cloak into Applications."},
    {"Open", "Launch Cloak from Applications. Builds are signed and notarized by Apple."},
    {"Choose",
     "Pick Local (10.21 GB MLX on 16 GB+ Macs) or NEAR AI Gateway (0 GB download on 8 GB+ Macs). Tor modes download the 5.69 GB Qwen 3.5 9B rewriter."},
    {"Start",
     "Local and direct NEAR AI Gateway work immediately. Press Start in the menu bar for Tor, Token Inference, zkAPI, Connected Apps, or the Pi agent."}
  ]
  @updates "Signed Sparkle updates check automatically unless disabled in Settings."

  # Official release checksums published alongside every signed build in
  # regents-ai/cloak-releases (`SHA256SUMS.txt` and `checksums.json`). Update
  # these values whenever a new release is published by `app/publish.sh`.
  @release_checksums %{
    tag: "0.2.0-278",
    dmg_filename: "Regents-Cloak-0.2.0-278.dmg",
    dmg_sha256: "25af4b52ad5b207cbbb6fe312006de7339921c24db2a523f61ef9c403908d150",
    # Populated on releases published by the updated app/release.sh + app/publish.sh
    # (e.g. {"Installed app binary SHA-256 (Cloak.app/Contents/MacOS/RegentsCloak)", "..."},
    # {"Apple Code Signature CDHash", "..."}).
    extra_hashes: [
      {"Apple Code Signature CDHash", "4cb692562950116b14ef4a5acf8ea7e0aa8cfb2b"}
    ],
    team_id: "367G3Z7G3J",
    release_url: "https://github.com/regents-ai/cloak-releases/releases/latest",
    sums_url: "https://raw.githubusercontent.com/regents-ai/cloak-releases/main/SHA256SUMS.txt",
    commands: [
      {"Verify DMG SHA-256", "shasum -a 256 ~/Downloads/Regents-Cloak.dmg"},
      {"Verify app binary SHA-256",
       "shasum -a 256 \"/Applications/Cloak.app/Contents/MacOS/RegentsCloak\""},
      {"Verify Apple signature (Team 367G3Z7G3J)",
       "codesign -dvv --strict \"/Applications/Cloak.app\""},
      {"Verify Apple notarization",
       "spctl --assess --type execute -vv \"/Applications/Cloak.app\""}
    ]
  }

  def heading, do: @heading
  def subtitle, do: @subtitle
  def pill, do: @pill
  def watch_label, do: @watch_label
  def watch_time, do: @watch_time
  def forum_label, do: @forum_label
  def forum_path, do: @forum_path
  def film, do: @film
  def releases_url, do: @releases_url
  def source_url, do: @source_url
  def docs_path, do: @docs_path
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

    #{@subtitle}

    - [#{@watch_label} (#{@watch_time})](#{film})
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
    - Full macOS verification commands (`shasum`, `codesign`, `spctl`) are listed on [/cloak/install#verify](#{RegentsWeb.PublicDocuments.url(@install_path <> "#verify")}) and live inside Cloak's **Settings → Status** pane.

    ## Needs

    #{@hardware}

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
