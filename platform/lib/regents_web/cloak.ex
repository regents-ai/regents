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
  @film "/images/cloak/intro.mp4"
  @releases_url "https://github.com/regents-ai/cloak-releases/releases"
  @source_url "https://github.com/regents-ai/cloak"
  @docs_path "/docs/cloak/reference"
  @facts "Apple silicon · macOS 26 or later · Cloak's privacy protections have not been independently audited."

  @agent %{
    title: "Local Agent Box & Connected Apps",
    summary:
      "Toggle the hammer in Token Inference or Anon V to run Cloak's built-in Pi coding agent inside an ephemeral, NIC-less Linux microVM—shell and file tools never touch your Mac, and every web or model request leaves through Tor with local prompt rephrasing. You can also connect Cursor, Cline, Aider, or any OpenAI-compatible Mac app via CloakDoor at http://127.0.0.1:8742/v1.",
    bullets: [
      "Isolated Linux VM: Pi's bash, read, edit, and write tools run inside a throwaway arm64 Linux microVM with zero access to your macOS files.",
      "Tor-only egress: All agent web traffic goes through torsocks, and model calls route through Cloak's local prompt rewriter and Anon V (zkAPI) or Boundless/Tempo (USDC.e).",
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
    {"Anon V",
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
    mode: "Anon V",
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
    switch: ["Local", "NEAR AI Gateway", "Token Inference", "Anon V", "Agent"],
    hint: "Phrasing changes locally while necessary identifiers like PR #418 stay intact."
  }

  @needs "Requirements depend on the mode. NEAR AI Gateway needs 8 GB+ RAM, 0 GB of model downloads, and a NEAR AI Cloud key. Local Mode (Fast MLX) needs a 16 GB+ Mac and downloads 10.21 GB (optional GGUF tiers: 13.63–17.63 GB on 24 GB+ Macs). Token Inference, Anon V, Connected Apps, and the sandboxed Pi agent need a 16 GB+ Mac and the 5.69 GB Qwen 3.5 9B local rewriter. Paid modes use Base USDC, Tempo USDC.e, ETH on Ethereum Mainnet, or your own Venice/NEAR API key."
  @caution "Cloak's privacy protections have not been independently audited. Understand each mode's limits—including what stays intact during prompt rephrasing and what passes through unchanged in Connected Apps—before relying on it for sensitive work."
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
        "Cloak is a native macOS menu bar application for Apple silicon; this page is product documentation and the chat window shown above is a static illustration of the Mac app, not a live hosted chat endpoint. Local runs entirely on the user's Mac through Apple MLX (vmlx-swift) or Metal llama.cpp with zero inference network traffic once model weights are downloaded, while NEAR AI Gateway, Token Inference, and Anon V send requests through external privacy-preserving inference backends. Every thread is isolated and locked to its mode on turn 1, and opt-in Local Access context (memory, approved folders, attachments, Calendar/Reminders/Contacts) stays strictly offline in Local Mode."
    },
    %{
      id: "modes-and-payments",
      summary: "Comparing the 4 modes, routing, and payment rails",
      body:
        "1) Local: runs Apple MLX (default Inkling 2 Mini JANGH2, 10.21 GB) or llama.cpp GGUF + optional uncensored LoRA directly on the Mac for free with no account, no inference network traffic, and no Tor startup required. 2) NEAR AI Gateway: verifies Intel TDX and NVIDIA GPU attestation locally on your Mac before encrypting prompts end-to-end (E2EE v2) to NEAR AI Cloud (Qwen3.8-27B) using a NEAR API key; Tor routing is optional, and opt-in Letta Trajectory v1 trace exports stay local until shared in the NEAR AI Gateway app. 3) Token Inference: rephrases user text locally and routes over per-conversation Tor circuits; defaults to Venice AI (local Base USDC wallet via x402, or optional Venice API key) and also supports Boundless (USDC.e on Tempo via MPP). 4) Anon V (zkAPI): rephrases user text locally, routes over Tor with optional live cover traffic, and pays each turn with a fresh one-time zero-knowledge credential from an Ethereum Mainnet ETH deposit. Cloak also includes the sandboxed Pi Local Agent Box (ephemeral NIC-less Linux microVM), Connected Apps (CloakDoor at http://127.0.0.1:8742/v1), Offline Data kits, and optional Darkbloom Inference Serving."
    },
    %{
      id: "requirements-and-install",
      summary: "Hardware requirements, model downloads, and install steps",
      body:
        "Requires an Apple silicon Mac running macOS 26 or later (macOS 27+ for optional Darkbloom Inference Serving). NEAR AI Gateway works on 8 GB+ Macs with 0 GB of model downloads. Local (Fast MLX) needs 16 GB+ RAM and downloads 10.21 GB (optional GGUF tiers: 13.63–17.63 GB on 24 GB+/32 GB+ Macs). Token Inference, Anon V, Connected Apps, and the sandboxed Pi agent need 16 GB+ RAM and the 5.69 GB Qwen 3.5 9B local prompt rewriter. Signed, notarized .dmg builds are published at https://github.com/regents-ai/cloak-releases/releases (source at https://github.com/regents-ai/cloak), and install steps are at /cloak/install. Neither /cloak nor /cloak/install serves the .dmg file directly."
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
    {"Drag",
     "Open Regents-Cloak.dmg from your Downloads folder and drag Cloak onto Applications."},
    {"Open",
     "Open Cloak from Applications. Apple has checked and notarized it, so your Mac only asks its usual question about apps from the internet."},
    {"Choose",
     "Cloak opens its Welcome Tour and checks your Mac's memory. Pick Local (10.21 GB MLX download on 16 GB+ Macs) or NEAR AI Gateway (0 GB download, works on 8 GB+ Macs); Tor modes download the 5.69 GB Qwen 3.5 9B rewriter."},
    {"Start",
     "Cloak lives in the menu bar and stays paused until you press Start. Local and direct NEAR AI Gateway work immediately; press Start in the crown menu for Tor routing, Token Inference, Anon V, Connected Apps, or the sandboxed Pi agent."}
  ]
  @updates "Cloak checks for signed Sparkle updates automatically unless you turn that off in Settings."

  def heading, do: @heading
  def subtitle, do: @subtitle
  def pill, do: @pill
  def watch_label, do: @watch_label
  def watch_time, do: @watch_time
  def film, do: @film
  def releases_url, do: @releases_url
  def source_url, do: @source_url
  def docs_path, do: @docs_path
  def agent, do: @agent
  def facts, do: @facts
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

  @doc "The page as Markdown, what `/cloak` answers when Markdown is asked for."
  def markdown do
    modes =
      @modes
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn
        {{name, nil, sentence}, n} ->
          "#{n}. **#{name}.** #{sentence}"

        {{name, credit, sentence}, n} ->
          "#{n}. **#{name}.** #{credit.before}[#{credit.link}](#{credit.href})#{credit.after} #{sentence}"
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
    - [View source](#{@source_url})
    - [#{@agent.docs_label}](#{RegentsWeb.PublicDocuments.url(@docs_path)})

    #{@facts}

    ## #{@modes_title}

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

    ## Needs

    #{@needs}

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

    """
    # #{@install_heading}

    #{@facts}

    - [View releases](#{@releases_url})
    - [View source](#{@source_url})

    #{steps}

    ## Updates

    #{@updates}

    ## Caution

    #{@caution}

    #{@feedback.before}[#{@feedback.link}](#{@feedback.href})#{@feedback.github_middle}[#{@feedback.github_link}](#{@feedback.github_href})#{@feedback.middle}[#{@feedback.social_link}](#{@feedback.social_href})#{@feedback.after}
    """
  end
end
