defmodule RegentsWeb.Cloak do
  @moduledoc """
  Regents Cloak's words, in the order `/cloak` shows them. The page
  (`RegentsWeb.CloakLive`) and its Markdown version (`markdown/0`) both read them
  from here.
  """
  use Boundary, deps: [RegentsWeb], exports: [CloakLive]

  # The heading's two lines (the second is set smaller) and the subtitle: change their words here. The subtitle's
  # first two sentences are also the page's description in `RegentsWeb.PublicDocuments`;
  # change them there too.
  @heading ["Cloak your local AI.", "Always private, full anon is optional."]
  @subtitle "Cloak is a small menu bar app for your Mac. Switch between using a local model with Llama v1.0.0 or using private NEAR inference. Then go “paranoid mode” with Tor, cover traffic, zkAPI, and message rewording when you need Vitalik-level privacy."

  @pill %{
    before: "Built on ",
    link: "llama.cpp",
    href: "https://github.com/ggml-org/llama.cpp",
    after: ", Tor and NEAR AI"
  }

  @watch_label "Watch the intro"
  @watch_time "0:20"
  @film "/images/cloak/intro.mp4"
  @facts "Apple silicon · macOS 26"

  @modes_title "4 modes of operation"

  # Each mode, in the app's order: its name, the quieter line under the name with
  # its link (or nil), its sentence.
  @modes [
    {"V",
     %{
       before: "Inspired by Vitalik's ",
       link: "X post",
       href: "https://x.com/VitalikButerin/status/2111046730959433793",
       after: " about his preferred AI usage."
     }, "Tor routing, cover traffic, prompt rewording, and zkAPI inference"},
    {"Token Inference",
     %{
       before: "Served by ",
       link: "Boundless",
       href: "https://boundless.network/news/mpp-payments",
       after: "."
     }, "Reworded on your Mac and sent through Tor. Pay per request with USDC.e on Tempo."},
    {"NEAR Private AI", nil,
     "Verifiably private AI models. Opt in to earn NEAR AI Cloud credits for shared traces."},
    {"Local Llama", nil,
     "Answered fully on your Mac with recommended best-in-class local models. Zero traffic is sent over the web."}
  ]

  # The drawn chat window: the app's own words and one sample exchange.
  @window %{
    title: "Chat",
    mode: "Local Llama",
    mode_note: "Answered on this Mac, with nothing to pay and no need to start Cloak.",
    asked: "Plan a quiet weekend in Lisbon.",
    answered:
      "Start with a slow morning in Alfama, then take the tram up to the viewpoint before lunch.",
    field: "Message",
    switch: ["V", "Token Inference", "NEAR Private AI", "Local Llama", "Agent"],
    hint: "The model on this Mac answers. Nothing is sent."
  }

  @hardware "16 GB of memory and 10 GB free. The app downloads a 5.7 GB model on first run."
  @needs @hardware <>
           " V takes a deposit of ETH, Token Inference takes USDC.e on Tempo, and NEAR Private AI takes a NEAR AI Cloud key. Cards are not accepted."

  @mode_access %{
    "V" => "ETH deposit",
    "Token Inference" => "USDC.e on Tempo",
    "NEAR Private AI" => "NEAR AI Cloud key",
    "Local Llama" => "Local model download"
  }
  @caution "This build is for testing. Its protections have not been independently checked, so don't rely on it for anything sensitive yet."
  @feedback %{
    before: "Something broke? Tell us at ",
    link: "patchbay.help/regents.sh",
    href: "https://patchbay.help/regents.sh",
    after: "."
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
        "Cloak is a native macOS menu bar application for Apple silicon; this page is product documentation and the chat window shown above is a static illustration of the Mac app, not a live hosted chat endpoint. Local Llama runs entirely on the user's Mac through llama.cpp with zero network traffic, while V, Token Inference, and NEAR Private AI send requests through external privacy-preserving inference backends."
    },
    %{
      id: "modes-and-payments",
      summary: "Comparing the 4 modes, routing, and payment rails",
      body:
        "1) V: routes through Tor with cover traffic, prompt rewording, and zkAPI inference; requires an ETH deposit. 2) Token Inference (Boundless): rewords prompts on the Mac and routes over Tor; pays per request with USDC.e on Tempo. 3) NEAR Private AI: verifiably private hosted models using a NEAR AI Cloud key, with optional trace sharing for NEAR AI Cloud credits. 4) Local Llama: runs recommended local models directly on the Mac for free with no web requests and no Tor startup required. Credit cards are not accepted."
    },
    %{
      id: "requirements-and-install",
      summary: "Hardware requirements, model download, and install steps",
      body:
        "Requires an Apple silicon Mac running macOS 26 with 16 GB memory and 10 GB free disk space. First run downloads a 5.7 GB local model before Local Llama can answer offline. Installation steps (drag Regents-Cloak.dmg into Applications, open, download the model, and optionally click Start in the menu bar for Tor-backed modes) are documented at /cloak/install. Neither /cloak nor /cloak/install serves the .dmg file directly."
    },
    %{
      id: "agent-discovery",
      summary: "How agents should read this page and report Cloak bugs",
      body:
        "Request /cloak or /cloak/install with Accept: text/markdown for plain Markdown output. For site-wide tools, OAuth/MCP endpoints, and agent pairing, read /llms.txt and /agents.md (or connect to /mcp). Report bugs or regressions in Cloak on Patchbay at /patchbay/regents.sh (or patchbay.help/regents.sh)."
    }
  ]

  # The install page, at `/cloak/install`: what to do with the app's file once a
  # person has it. The page offers no file. Each step: its one-word title, its
  # sentence.
  # The app's chief checks these against each build.
  @install_path "/cloak/install"
  @install_heading "Install Cloak"
  @install_steps [
    {"Build",
     "Start with the signed Regents-Cloak.dmg provided with your build. The install page guides you once you have that file."},
    {"Drag",
     "Open Regents-Cloak.dmg from your Downloads folder and drag Cloak onto Applications."},
    {"Open",
     "Open Cloak from Applications. Apple has checked and signed it, so your Mac only asks its usual question about apps from the internet."},
    {"Model",
     "Cloak opens its Chat window and shows its modes once. Press Download Model and let the 5.7 GB model finish. Local Llama then answers on your Mac with nothing to pay."},
    {"Start",
     "Cloak lives in the menu bar and stays paused until you press Start. Click the small crown at the top right of your screen. Start is for the modes that send through Tor; Local Llama doesn't need it."}
  ]
  @updates "Cloak keeps itself up to date, unless you turn that off in Settings."

  def heading, do: @heading
  def subtitle, do: @subtitle
  def pill, do: @pill
  def watch_label, do: @watch_label
  def watch_time, do: @watch_time
  def film, do: @film
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
      Enum.map_join(@modes, "\n", fn
        {name, nil, sentence} ->
          "| #{name} | #{sentence} | #{@mode_access[name]} |"

        {name, credit, sentence} ->
          "| #{name} | #{String.trim_trailing(sentence, ".")}. #{credit.before}[#{credit.link}](#{credit.href})#{credit.after} | #{@mode_access[name]} |"
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

    [#{@watch_label} #{@watch_time}](#{film})

    #{@facts}

    ## #{@modes_title}

    | Mode | Where the prompt is handled | What you need |
    | --- | --- | --- |
    #{modes}

    ## #{@agent_docs_title}

    #{@agent_docs_intro}

    #{agent_docs}

    ## Needs

    #{@hardware}

    ## Caution

    #{@caution}

    #{@feedback.before}[#{@feedback.link}](#{@feedback.href})#{@feedback.after}
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

    #{steps}

    ## Updates

    #{@updates}

    ## Caution

    #{@caution}

    #{@feedback.before}[#{@feedback.link}](#{@feedback.href})#{@feedback.after}
    """
  end
end
