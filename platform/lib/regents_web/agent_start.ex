defmodule RegentsWeb.AgentStart do
  @moduledoc """
  The steps that connect a person's agent to their Regents account, for each
  agent Regents names. The `/start` page shows them to people and serves the
  same text as Markdown to agents, so the two never differ.
  """

  # How each agent reaches Regents: the regents command line, or the SIWA sign-in
  # client served by siwa.regents.sh for agents that run Python or Node without it.
  @agents [
    %{id: "hermes", label: "Hermes", name: "Hermes", harness: "hermes", client: :cli},
    %{id: "codex", label: "Codex", name: "Codex", harness: "codex", client: :cli},
    %{id: "grok_bot", label: "Grok Bot", name: "Grok Bot", harness: "grok_bot", client: :siwa},
    %{id: "muse", label: "Muse", name: "Muse", harness: "muse", client: :siwa},
    %{id: "dots", label: "Dots", name: "Dots", harness: "dots", client: :siwa},
    %{
      id: "other",
      label: "Other agents",
      name: "<your name>",
      harness: "<harness>",
      client: :cli
    }
  ]

  @harnesses "hermes, grok_bot, muse, openclaw, nemoclaw, ironclaw, pi, claude_code, codex, cursor, gemini_cli, dots or other"

  def agents, do: @agents

  defp origin, do: RegentsWeb.PublicDocuments.url("")

  def agent(id), do: Enum.find(@agents, hd(@agents), &(&1.id == id))

  @doc "What a person gives their agent: the steps for its client, ready to paste."
  def instruction(%{client: :cli} = agent) do
    """
    Connect to my Regents account. I'll paste you a message with a pairing code; I make it with Pair New Agent in the side panel at #{origin()}.

    1. Install the Regents command line and check it. Expect 1.10.12.
       uv tool install regents-cli==1.10.12
       regents --version
    2. Sign in to Regents, then check. Sign in only with the key I gave you; this makes a new key when none is there, so ask me first. Never show the key.
       regents auth login --site regents
       regents protocol doctor
    3. Check who you are signed in as. It shows no pairing until you pair.
       regents protocol agents whoami --json
    4. Pair. With your file tool, not the shell, write my code into pair.json in your home folder, never inside a project:
       {"code": "<CODE>", "name": "#{agent.name}", "harness": "#{agent.harness}"}
       Then pair from that file and delete it, whether pairing worked or not:
       regents protocol agents pair --json < ~/pair.json
       rm ~/pair.json
    5. Check in:
       regents protocol agents me
    6. Read my account when I ask:
       regents protocol account show
       regents protocol account balances
       regents protocol account budget
       regents protocol account credits-history
       regents protocol account claims
       regents protocol account points
       regents protocol staking position
    #{other_harness(agent)}
    These steps only read. Never spend, sign a transaction or run regents auth register.\
    """
  end

  def instruction(%{client: :siwa} = agent) do
    """
    Connect to my Regents account. I'll paste you a message with a pairing code; I make it with Pair New Agent in the side panel at #{origin()}.

    1. Get the Regent sign-in client:
       curl -fsSO https://siwa.regents.sh/agent/siwa_agent.py
    2. Make your key if you have none. Keep an existing one; never show it.
       uv run siwa_agent.py keygen
    3. Pair. With your file tool, not the shell, write my code into pair.json in your home folder, never inside a project:
       {"code": "<CODE>", "name": "#{agent.name}", "harness": "#{agent.harness}"}
       Then pair from that file and delete it, whether pairing worked or not:
       uv run siwa_agent.py pair #{origin()} < ~/pair.json
       rm ~/pair.json
    4. Check in:
       uv run siwa_agent.py me #{origin()}
    5. Read my account when I ask:
       uv run siwa_agent.py request GET #{origin()}/api/agent/v1/account
       uv run siwa_agent.py request GET #{origin()}/api/agent/v1/credits/balance
       uv run siwa_agent.py request GET #{origin()}/api/agent/v1/credits/budget
       uv run siwa_agent.py request POST #{origin()}/api/agent/v1/credits/history --body '{}'
       uv run siwa_agent.py request POST #{origin()}/api/agent/v1/claims --body '{}'
       uv run siwa_agent.py request GET #{origin()}/api/agent/v1/points
       uv run siwa_agent.py request GET #{origin()}/api/agent/v1/staking/position
    #{broker_note(agent)}
    These steps only read. Never spend, sign a transaction or run register-agent.\
    """
  end

  defp other_harness(%{id: "other"}), do: "\nharness is one of: #{@harnesses}.\n"
  defp other_harness(_agent), do: ""

  defp broker_note(%{id: "muse"}),
    do:
      "\nIf siwa.regents.sh doesn't answer from your host, set SIWA_BROKER=https://siwa-server.fly.dev and try again.\n"

  defp broker_note(_agent), do: ""

  @doc "The page as Markdown, for agents that ask for it."
  def markdown do
    """
    # Connect your agent to Regents

    Your agent pairs with your Regents account and reads it for you: your account, Credits, names, Points and staking. It can't spend, sign or change anything. Agent spending opens soon.

    1. Your person makes a pairing code with Pair New Agent in the side panel of #{origin()}. A code works once, for ten minutes.
    2. Follow the steps for your agent below, with that code.
    3. Your agent then shows under its name in their side panel and on their account page.

    A refusal names what went wrong: `pairing_failed` means the code is used, expired or mistyped, so ask for a new one; `not_paired` means you were unpaired.

    #{Enum.map_join(@agents, "\n", &section/1)}\
    """
  end

  defp section(agent) do
    """
    ## #{agent.label}

    ```text
    #{instruction(agent)}
    ```
    """
  end
end
