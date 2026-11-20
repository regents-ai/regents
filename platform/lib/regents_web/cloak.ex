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

  # Always the newest signed build.
  @download "https://github.com/regents-ai/cloak-releases/releases/latest/download/Regents-Cloak.dmg"
  @download_label "Download for Mac"
  @watch_label "Watch the intro"
  @watch_time "0:20"
  @film "/images/cloak/intro.mp4"
  @facts "Early test build · 130 MB · Apple silicon · macOS 26"

  @modes_title "3 modes of operation"

  # Each mode: its name, the quieter line under the name with its link (or nil), its sentence.
  @modes [
    {"Anon “paranoid mode”",
     %{
       before: "Inspired by Vitalik's ",
       link: "X post",
       href: "https://x.com/VitalikButerin/status/2111046730959433793",
       after: " about his preferred AI usage."
     }, "Reworded on your Mac, then sent through Tor."},
    {"NEAR Private AI", nil, "Proof of NEAR's servers is checked before anything is sent."},
    {"Local Llama", nil, "Answered on your Mac. Nothing is sent."}
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
    switch: ["Anon", "NEAR Private AI", "Local Llama", "Agent"],
    hint: "The model on this Mac answers. Nothing is sent."
  }

  @needs "16 GB of memory and 10 GB free; the app downloads a 6.5 GB model on first run. Modes 1 and 2 also need about 1 USDC.e on Tempo, or a NEAR AI Cloud key."
  @caution "This build is for testing. Its protections have not been independently checked, so don't rely on it for anything sensitive yet."
  @feedback %{
    before: "Something broke? Tell us at ",
    link: "patchbay.help/regents.sh",
    href: "https://patchbay.help/regents.sh",
    after: "."
  }

  def heading, do: @heading
  def subtitle, do: @subtitle
  def pill, do: @pill
  def download, do: @download
  def download_label, do: @download_label
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

    film = RegentsWeb.Endpoint.static_url() <> RegentsWeb.Endpoint.static_path(@film)

    """
    #{@pill.before}[#{@pill.link}](#{@pill.href})#{@pill.after}

    # #{Enum.join(@heading, " ")}

    #{@subtitle}

    [#{@download_label}](#{@download}) · [#{@watch_label} #{@watch_time}](#{film})

    #{@facts}

    ## #{@modes_title}

    #{modes}

    ## Needs

    #{@needs}

    ## Caution

    #{@caution}

    #{@feedback.before}[#{@feedback.link}](#{@feedback.href})#{@feedback.after}
    """
  end
end
