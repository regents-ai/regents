defmodule RegentsWeb.Cloak do
  @moduledoc """
  Regents Cloak: a private local agent in one Mac app. `/cloak` shows it as
  Cloak's own README (14 Nov) does: in development, with no release and no
  protection proven, so every protection and card reads as planned and the
  download stays off.
  """

  @features [
    "Works with the agents you already use: a local OpenAI-compatible address on your Mac.",
    "A local model redacts and rephrases each prompt before it leaves.",
    "A fresh Tor circuit for every conversation.",
    "Cover requests hide when you are really working.",
    "Pay per request with zkAPI, without showing a wallet address.",
    "The agent runs sandboxed, with every connection sent through Tor."
  ]

  @protections [
    %{
      title: "Private rewriting",
      copy:
        "A local model redacts and rephrases each prompt on your Mac, so the cloud model sees altered text, not your raw words."
    },
    %{
      title: "Private payments",
      copy: "zkAPI: deposit ETH and pay for each request without revealing your wallet address."
    },
    %{
      title: "Separate chats",
      copy: "Each conversation opens on a fresh Tor circuit, apart from the others."
    },
    %{
      title: "Private network",
      copy: "Every outbound call is forced through Tor, so nothing goes around it."
    },
    %{
      title: "Decoy traffic",
      copy: "Random cover requests mix in with real ones to obscure timing patterns."
    },
    %{
      title: "Contained agent",
      copy: "The agent runs in isolation and reaches only the files and tools you allow."
    }
  ]

  @limits [
    "Slower on purpose: Tor and cover traffic add delay, most of it at startup.",
    "The model you use still reads what you send it, after rewriting.",
    "Rewording covers the messages you write; system messages, tool results and files go as sent.",
    "Built first against passive watchers: a provider that logs, or a network that observes.",
    "A provider working with a Tor relay can still match requests by their timing; cover traffic is not foolproof.",
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
        "Planned: a local model redacts and rephrases each prompt, so the cloud model never sees your raw words.",
      tint: "#a97bf0"
    },
    %{
      id: "cloak/circuit",
      name: "Tor circuits",
      headline: "A circuit per conversation.",
      line: "Planned: every conversation opens on a fresh Tor circuit.",
      tint: "#b488f0"
    },
    %{
      id: "cloak/cover",
      name: "Cover traffic",
      headline: "Quiet looks like busy.",
      line: "Planned: random cover requests mix in with real ones to hide timing patterns.",
      tint: "#5fa8a0"
    },
    %{
      id: "cloak/sandbox",
      name: "Sandbox",
      headline: "The agent stays in its box.",
      line: "Planned: the agent runs in isolation, with every outbound call forced through Tor.",
      tint: "#8aa0b8"
    }
  ]

  @post "https://x.com/VitalikButerin/status/2111046730959433793"

  def cards,
    do: Enum.map(@cards, &Map.merge(&1, %{action: "See protections", href: "/cloak#protections"}))

  def features, do: @features
  def protections, do: @protections
  def limits, do: @limits
  def post, do: @post
end
