defmodule RegentsWeb.Cloak do
  @moduledoc """
  Regents Cloak's words, in the order `/cloak` shows them: the text the founder
  approved on 20 Nov 2026, word for word. The page (`RegentsWeb.CloakLive`) and
  its Markdown version (`markdown/0`) both read them from here.
  """

  @top_line "regents.sh/cloak · Cloak — Mac app"
  @heading "A Mac app that rewords your messages and sends them through Tor."
  @note "Early test build for invited testers."

  @points [
    {"Reworded.", "A model on your Mac rewrites each message before it leaves."},
    {"Tor.",
     "Each chat takes its own route through the Tor network, and can add decoy traffic beside it."},
    {"Proof.", "In NEAR chats, Cloak checks proof of NEAR's servers before it sends anything."}
  ]

  @about "Cloak sets up and runs the agent setup Vitalik Buterin described in October 2026: messages reworded by a model on your own Mac, sent over Tor, with an agent that works inside a sealed box. It is built on open-source work: llama.cpp, Tor, the Pi agent, zkAPI and NEAR AI's verification code."

  @caution "This build is for testing. Its protections have not been independently checked, so don't rely on it for anything sensitive yet. Payment through zkAPI isn't in this build: messages are paid from a wallet on your Mac, or with your own NEAR AI key."

  @needs "A Mac with Apple silicon and 16 GB of memory. macOS 26 or later. 10 GB of free space; the app downloads a 6.5 GB model on first run. To send messages: about 1 USDC.e on Tempo, or a NEAR AI Cloud key."

  @install [
    "Download Regents Cloak and open the file.",
    "Drag Regents Cloak into Applications, then open it.",
    "Download the model when the app asks, then choose Start from the menu bar."
  ]

  # Always the newest signed build.
  @download "https://github.com/regents-ai/cloak-releases/releases/latest/download/Regents-Cloak.dmg"
  @updates "Updates itself"
  @feedback "Something broke? Tell Sean what you did and what you saw."

  def top_line, do: @top_line
  def heading, do: @heading
  def note, do: @note
  def points, do: @points
  def about, do: @about
  def caution, do: @caution
  def needs, do: @needs
  def install, do: @install
  def download, do: @download
  def updates, do: @updates
  def feedback, do: @feedback

  @doc "The page as Markdown, what `/cloak` answers when Markdown is asked for."
  def markdown do
    points = Enum.map_join(@points, "\n\n", fn {word, sentence} -> "**#{word}** #{sentence}" end)

    steps =
      @install |> Enum.with_index(1) |> Enum.map_join("\n", fn {step, n} -> "#{n}. #{step}" end)

    """
    #{@top_line}

    # #{@heading}

    #{@note}

    #{points}

    ## About

    #{@about}

    #{@caution}

    ## Needs

    #{@needs}

    ## Install

    #{steps}

    [Download](#{@download})

    #{@updates}

    #{@feedback}
    """
  end
end
