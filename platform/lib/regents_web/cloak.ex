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
    "Run locally, or control how prompts reach the cloud."
  ]
  @subtitle "Run a model on your Mac, or choose how a conversation reaches a cloud model. Cloak gives you controls for hardware-verified enclaves, local prompt rephrasing, Tor routing, and accountless crypto payments—so you can see what leaves your Mac and what can link one request to another."

  @pill %{
    before: "Built on Apple MLX, ",
    link: "llama.cpp",
    href: "https://github.com/ggml-org/llama.cpp",
    after: ", Tor and NEAR AI"
  }

  @watch_label "Watch the intro"
  @watch_time "0:35"
  @forum_label "Cloak Forum"
  @forum_path "/patchbay/cloak"
  @film "/images/cloak/intro.mp4"
  @releases_url "https://github.com/regents-ai/cloak-releases/releases"
  @source_url "https://github.com/regents-ai/cloak"
  @docs_path "/docs/cloak/reference"
  @facts "v0.2.0 Beta · Apple silicon · macOS 26 or later · Not yet independently audited · Keep wallet balances small."

  @ecosystem_heading "Built on the open privacy & payment stack"
  @ecosystem [
    %{
      id: "boundless-tempo",
      note: "Token Inference · MPP USDC.e",
      partners: [
        %{id: "boundless", name: "Boundless", href: "https://boundless.network"},
        %{id: "tempo", name: "Tempo", href: "https://tempo.xyz"}
      ]
    },
    %{
      id: "venice-base",
      note: "Token Inference · x402 USDC",
      partners: [
        %{id: "venice", name: "Venice", href: "https://venice.ai"},
        %{id: "base", name: "Base", href: "https://base.org"}
      ]
    },
    %{
      id: "eigenlayer",
      note: "Verifiable compute",
      partners: [
        %{id: "eigenlayer", name: "EigenLayer", href: "https://eigenlayer.xyz"}
      ]
    },
    %{
      id: "ethereum",
      note: "zkAPI ETH settlement",
      partners: [
        %{id: "ethereum", name: "Ethereum", href: "https://ethereum.org"}
      ]
    }
  ]

  @agent %{
    title: "Local Agent Box & Connected Apps",
    summary:
      "Toggle the hammer in Token Inference or zkAPI Anon Inference to run Cloak's built-in Pi coding agent inside an ephemeral, NIC-less Linux microVM—shell and file tools never touch your Mac, and every web or model request leaves through Tor with local prompt rephrasing. You can also connect Cursor, Cline, Aider, or any OpenAI-compatible Mac app via CloakDoor at http://127.0.0.1:8742/v1.",
    bullets: [
      "Isolated Linux VM: Pi's bash, read, edit, and write tools run inside a throwaway arm64 Linux microVM with zero access to your macOS files.",
      "Tor-only egress: All agent web traffic goes through torsocks, and model calls route through Cloak's local prompt rewriter and zkAPI Anon Inference or Boundless/Tempo (USDC.e).",
      "Clear boundaries: Connecting an external Mac app changes its inference endpoint (not its macOS permissions), and CloakDoor rephrases user-message text only—tool results and code pass through unchanged."
    ],
    docs_label: "Read the Cloak documentation",
    docs_href: "/docs/cloak/reference"
  }

  @modes_title "4 modes of operation"

  # Each mode, in the order a new user decides: local first, then each remote
  # option with what the provider can see and what can link requests.
  @modes [
    {"Local", nil,
     "The model answers on your Mac using Apple MLX or llama.cpp. Once weights are downloaded, your conversation does not go to an inference provider—no account and nothing to pay."},
    {"NEAR AI Gateway",
     %{
       before: "Hardware-verified on ",
       link: "NEAR AI Cloud",
       href: "https://cloud.near.ai",
       after: "."
     },
     "Cloak verifies Intel TDX and NVIDIA GPU attestation on your Mac before encrypting your prompt end-to-end. Messages are sent as written, your NEAR API key still identifies your account, and Tor is optional. Opt-in trace exports stay local until you share them in the NEAR AI Gateway app."},
    {"Token Inference",
     %{
       before: "Served by ",
       link: "Venice AI",
       href: "https://venice.ai",
       after: " (default) or Boundless."
     },
     "User text is rephrased locally and sent over a per-conversation Tor circuit. Pay from a local Base USDC wallet (x402), a Venice API key, or Tempo USDC.e via Boundless. Venice's Private and TEE tiers are provider-reported, and a reused wallet or key can link chats."},
    {"zkAPI Anon Inference",
     %{
       before: "Inspired by Vitalik's ",
       link: "X post",
       href: "https://x.com/VitalikButerin/status/2111046730959433793",
       after: " on private AI payments."
     },
     "Rephrased locally, routed over Tor with optional live cover traffic, and paid with a fresh one-time zkAPI credential from an ETH deposit—avoiding a reusable wallet or key on each model call. Identifying text, conversation history, and timing can still connect requests."}
  ]

  # The drawn chat window: a synthetic Original -> Sent exchange that shows both
  # what local rephrasing changes (style and irrelevant framing) and what it
  # intentionally keeps (necessary identifiers such as PR #418).
  @window %{
    title: "Chat",
    mode: "zkAPI Anon Inference",
    mode_note: "Rephrased locally · Tor circuit · One-time zkAPI credential",
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
    hint: "Phrasing changes locally while necessary identifiers like PR #418 stay intact."
  }

  @hardware "Apple silicon Mac with macOS 26+. NEAR AI Gateway needs 8 GB+ RAM (0 GB download); Local Mode (Fast MLX) needs 16 GB+ RAM (10.21 GB download); Tor modes and Pi agent need 16 GB+ RAM (5.69 GB Qwen 3.5 9B rewriter)."
  @needs "Requirements depend on the mode. NEAR AI Gateway needs 8 GB+ RAM, 0 GB of model downloads, and a NEAR AI Cloud key. Local Mode (Fast MLX) needs a 16 GB+ Mac and downloads 10.21 GB (optional GGUF tiers: 13.63–17.63 GB on 24 GB+ Macs). Token Inference, zkAPI Anon Inference, Connected Apps, and the sandboxed Pi agent need a 16 GB+ Mac and the 5.69 GB Qwen 3.5 9B local rewriter. Paid modes use Base USDC, Tempo USDC.e, ETH on Ethereum Mainnet, or your own Venice/NEAR API key."

  @mode_access %{
    "Local" => "Free local model download (10.21 GB MLX)",
    "NEAR AI Gateway" => "NEAR AI Cloud API key",
    "Token Inference" => "Base USDC (Venice x402), Venice key, or Tempo USDC.e (Boundless MPP)",
    "zkAPI Anon Inference" => "ETH deposit on Ethereum Mainnet (30-day protocol limit)"
  }
  @caution "Cloak v0.2 is beta software and its privacy protections have not been independently audited. Keep wallet balances small, back up or withdraw funds before wiping your Mac (keys never sync to iCloud), and note the 30-day protocol limit on untouched zkAPI deposits."
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
  @agent_docs_intro "Expand any section below for structured facts about Cloak's runtime boundary, privacy modes, requirements, and Regents integration."
  @agent_docs [
    %{
      id: "runtime-boundary",
      summary: "Runtime boundary: macOS desktop app (no live web chat backend)",
      body:
        "Cloak is a native macOS menu bar application for Apple silicon; this page is product documentation and the chat window shown above is a static illustration of the Mac app, not a live hosted chat endpoint. Local runs entirely on the user's Mac through Apple MLX (vmlx-swift) or Metal llama.cpp with zero inference network traffic once model weights are downloaded, while NEAR AI Gateway, Token Inference, and zkAPI Anon Inference send requests through external privacy-preserving inference backends. Every thread is isolated and locked to its mode on turn 1, and opt-in Local Access context (memory, approved folders, drag-and-drop PDF/document/image-OCR/code attachments, Calendar/Reminders/Contacts) stays strictly offline in Local Mode."
    },
    %{
      id: "modes-and-payments",
      summary: "Comparing the 4 modes, routing, and payment rails",
      body:
        "1) Local: runs Apple MLX (default Inkling 2 Mini JANGH2, 10.21 GB) or llama.cpp GGUF + optional uncensored LoRA directly on the Mac for free with no account, no inference network traffic, and no Tor startup required. 2) NEAR AI Gateway: verifies Intel TDX and NVIDIA GPU attestation locally on your Mac before encrypting prompts end-to-end (E2EE v2) to NEAR AI Cloud (Qwen3.8-27B) using a NEAR API key; Tor routing is optional, and opt-in Letta Trajectory v1 trace exports stay local until shared in the NEAR AI Gateway app. 3) Token Inference: rephrases user text locally and routes over per-conversation Tor circuits; defaults to Venice AI (local Base USDC wallet via x402, or optional Venice API key) and also supports Boundless (USDC.e on Tempo via MPP). 4) zkAPI Anon Inference: rephrases user text locally, routes over Tor with optional live cover traffic, and pays each turn with a fresh one-time zero-knowledge credential from an Ethereum Mainnet ETH deposit. Cloak also includes the sandboxed Pi Local Agent Box (ephemeral NIC-less Linux microVM), Connected Apps (CloakDoor at http://127.0.0.1:8742/v1), progressive Offline Data packs (Kiwix, DevDocs, CourtListener, PubMed Central, Tinfoil Kit), and optional Darkbloom Inference Serving (macOS 27+, Off / Local Only / Network + Local)."
    },
    %{
      id: "requirements-and-install",
      summary: "Hardware requirements, model downloads, and install steps",
      body:
        "Requires an Apple silicon Mac running macOS 26 or later (macOS 27+ for optional Darkbloom Inference Serving). NEAR AI Gateway works on 8 GB+ Macs with 0 GB of model downloads. Local (Fast MLX) needs 16 GB+ RAM and downloads 10.21 GB (optional GGUF tiers: 13.63–17.63 GB on 24 GB+/32 GB+ Macs). Token Inference, zkAPI Anon Inference, Connected Apps, and the sandboxed Pi agent need 16 GB+ RAM and the 5.69 GB Qwen 3.5 9B local prompt rewriter. Signed, notarized .dmg builds (Apple Developer ID Team 367G3Z7G3J) and SHA-256 checksums (SHA256SUMS.txt / checksums.json) are published at https://github.com/regents-ai/cloak-releases/releases (source at https://github.com/regents-ai/cloak), and install and verification steps are at /cloak/install. Neither /cloak nor /cloak/install serves the .dmg file directly."
    },
    %{
      id: "agent-discovery",
      summary: "How agents should read this page and report Cloak bugs",
      body:
        "Request /cloak, /cloak/install, /docs/cloak, or /docs/cloak/reference with Accept: text/markdown for plain Markdown output. For site-wide tools, OAuth/MCP endpoints, and agent pairing, read /llms.txt and /agents.md (or connect to /mcp). Report bugs, regressions, or feedback on Patchbay at https://regents.sh/patchbay/cloak, open an issue at https://github.com/regents-ai/cloak, or email build@regents.sh."
    }
  ]

  # The install page, at `/cloak/install`: what to do with the app's file once a
  # person has it. Each step: its one-word title and its sentence.
  @install_path "/cloak/install"
  @install_heading "Install Cloak"
  @install_steps [
    {"Build",
     "Start with the signed Regents-Cloak.dmg provided with your build. The install page guides you once you have that file."},
    {"Drag",
     "Open Regents-Cloak.dmg from your Downloads folder and drag Cloak onto Applications."},
    {"Open",
     "Open Cloak from Applications. Apple has checked and notarized it, so your Mac only asks its usual question about apps from the internet."},
    {"Choose",
     "Cloak opens its Welcome Tour and checks your Mac's memory. Pick Local (10.21 GB MLX download on 16 GB+ Macs) or NEAR AI Gateway (0 GB download, works on 8 GB+ Macs); Tor modes download the 5.69 GB Qwen 3.5 9B rewriter."},
    {"Start",
     "Cloak lives in the menu bar and stays paused until you press Start. Local and direct NEAR AI Gateway work immediately; press Start in the crown menu for Tor routing, Token Inference, zkAPI Anon Inference, Connected Apps, or the sandboxed Pi agent."}
  ]
  @updates "Cloak checks for signed Sparkle updates automatically unless you turn that off in Settings."

  # Official release checksums published alongside every signed build in
  # regents-ai/cloak-releases (`SHA256SUMS.txt` and `checksums.json`). Update
  # these values whenever a new release is published by `app/publish.sh`.
  @release_checksums %{
    tag: "0.5.4-179",
    dmg_filename: "Regents-Cloak-0.5.4-179.dmg",
    dmg_sha256: "f113bb85e9ab27504232b6999ebd807ef27546938442b2d3b2cf9995a3db2f5e",
    # Populated on releases published by the updated app/release.sh + app/publish.sh
    # (e.g. {"Installed app binary SHA-256 (Cloak.app/Contents/MacOS/RegentsCloak)", "..."},
    # {"Apple Code Signature CDHash", "..."}).
    extra_hashes: [],
    team_id: "367G3Z7G3J",
    release_url: "https://github.com/regents-ai/cloak-releases/releases/latest",
    sums_url: "https://raw.githubusercontent.com/regents-ai/cloak-releases/main/SHA256SUMS.txt",
    commands: [
      {"Verify downloaded DMG SHA-256 (macOS built-in shasum)",
       "shasum -a 256 ~/Downloads/Regents-Cloak.dmg"},
      {"Verify installed app binary SHA-256 (compare with Settings → Status)",
       "shasum -a 256 \"/Applications/Cloak.app/Contents/MacOS/RegentsCloak\""},
      {"Verify Apple Developer ID signature & CDHash (Team 367G3Z7G3J)",
       "codesign -dvv --strict \"/Applications/Cloak.app\""},
      {"Verify Apple Notarization & Gatekeeper",
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

        {name, credit, sentence} ->
          "| #{name} | #{String.trim_trailing(sentence, ".")}. #{credit.before}[#{credit.link}](#{credit.href})#{credit.after} | #{@mode_access[name]} |"
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
    #{@pill.before}[#{@pill.link}](#{@pill.href})#{@pill.after}

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
