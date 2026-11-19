defmodule RegentAgents.Harness do
  @moduledoc "What an agent runs on. `other` is for anything not listed."

  use Ash.Type.Enum,
    values: [
      hermes: [label: "Hermes"],
      grok_bot: [label: "Grok Bot"],
      muse: [label: "Muse"],
      openclaw: [label: "OpenClaw"],
      nemoclaw: [label: "NemoClaw"],
      ironclaw: [label: "IronClaw"],
      pi: [label: "Pi"],
      claude_code: [label: "Claude Code"],
      codex: [label: "Codex"],
      chatgpt: [label: "ChatGPT"],
      claude: [label: "Claude"],
      cursor: [label: "Cursor"],
      gemini_cli: [label: "Gemini CLI"],
      dots: [label: "Dots"],
      other: [label: "Other"]
    ]

  @doc """
  The ten agents the pairing box offers, in its order: any agent, OpenAI's Codex,
  Grok Bot, Muse, Hermes, Dots, IronClaw, OpenClaw, Claude Code and Pi. Every
  site offers all ten (`RegentAgents.PairingMessage` has their words). An agent
  on any other harness, NemoClaw among them, pairs as any agent.
  """
  def featured,
    do: [
      :other,
      :codex,
      :grok_bot,
      :muse,
      :hermes,
      :dots,
      :ironclaw,
      :openclaw,
      :claude_code,
      :pi
    ]

  @doc """
  The hosted runtimes: apps that pair through a site's hosted connection
  (`regent_mcp_agents`) rather than a key of their own.
  """
  def hosted_runtimes, do: [:chatgpt, :claude]

  @doc """
  The hosted runtimes this site offers, from
  `config :regent_agents, hosted_pairing: [:claude]`. A site lists only the apps
  whose connection it serves, so switching on Claude does not offer ChatGPT.
  """
  def hosted do
    configured = Application.get_env(:regent_agents, :hosted_pairing, [])
    Enum.filter(hosted_runtimes(), &(&1 in configured))
  end

  @doc "The agents a site's pairing box offers: every agent but the hosted runtimes it does not serve."
  def offered, do: values() -- (hosted_runtimes() -- hosted())
end
