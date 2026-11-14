defmodule RegentsWeb.Cloak do
  @moduledoc """
  Regents Cloak: one Mac app to install and run a private agent stack. `/cloak`
  shows it as Cloak's own README (14 Nov) does: in development, with no release
  and no protection proven, so every protection and card reads as planned and
  the download stays off.
  """

  @protections [
    %{
      title: "Private rewriting",
      copy: "Each message you write is reworded on your Mac before it leaves."
    },
    %{title: "Private payments", copy: "Pay for each request without an account tied to you."},
    %{title: "Separate chats", copy: "Conversations are kept apart from each other."},
    %{
      title: "Private network",
      copy: "The agent's requests are routed through a private network."
    },
    %{title: "Decoy traffic", copy: "Decoy requests make real ones harder to spot."},
    %{title: "Contained agent", copy: "The agent reaches only the files and tools you allow."}
  ]

  @limits [
    "The model you use still reads what you send it, after rewriting.",
    "Rewording covers the messages you write; system messages, tool results and files go as sent.",
    "Someone watching both ends of a connection may still match requests by their timing.",
    "Until every release passes its tests, some programs may connect without a private network.",
    "Cloak protects your agent's work, not the rest of your Mac.",
    "Each protection must pass its tests before release."
  ]

  # The template's four Cloak cards (`AshTemplateWeb.ValueCardsLive`, ash-template
  # 4d972bbc^). Cloak has no site of its own, so each opens the Protections on
  # its page.
  @cards [
    %{
      id: "cloak/rewrite",
      name: "Rewriting",
      headline: "Rewritten before it leaves.",
      line:
        "Planned: a local model on your Mac rewords each message you write before it is sent.",
      tint: "#a97bf0"
    },
    %{
      id: "cloak/circuit",
      name: "Tor circuits",
      headline: "A circuit per conversation.",
      line: "Planned: each conversation travels over its own Tor circuit.",
      tint: "#b488f0"
    },
    %{
      id: "cloak/cover",
      name: "Cover traffic",
      headline: "Quiet looks like busy.",
      line: "Planned: cover traffic runs alongside your real requests.",
      tint: "#5fa8a0"
    },
    %{
      id: "cloak/sandbox",
      name: "Sandbox",
      headline: "The agent stays in its box.",
      line: "Planned: the whole agent runs inside a sandbox, with its network sent through Tor.",
      tint: "#8aa0b8"
    }
  ]

  @post "https://x.com/VitalikButerin/status/2111046730959433793"

  def cards,
    do: Enum.map(@cards, &Map.merge(&1, %{action: "See protections", href: "/cloak#protections"}))

  def protections, do: @protections
  def limits, do: @limits
  def post, do: @post
end
