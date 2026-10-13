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

  @doc "The address of the steps for an agent on `harness`."
  def link(harness) do
    id = Atom.to_string(harness)
    id = if Enum.any?(@agents, &(&1.id == id)), do: id, else: "other"
    "#{origin()}/start?agent=#{id}"
  end

  @doc "What a person gives their agent: the steps for its client, ready to paste."
  def instruction(%{client: :cli} = agent) do
    """
    Connect to my Regents account. Ask me for a pairing code first; I make it on my Account page at #{origin()}/account.

    1. Install the Regents command line, version 1.9.3 or newer. To run it without installing, use uvx --from regents-cli==1.9.3 regents wherever these steps say regents.
       uv tool install --upgrade regents-cli
    2. Sign in to Regents. This makes your agent key the first time. Never show the key.
       regents auth login --site regents
    3. Pair, sending my code on stdin. Never put the code in a command argument or a reply.
       printf '%s' '{"code":"<CODE>","name":"#{agent.name}","harness":"#{agent.harness}"}' | regents protocol agents pair
    4. Check in:
       regents protocol agents me
    5. Read my account when I ask:
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
    Connect to my Regents account. Ask me for a pairing code first; I make it on my Account page at #{origin()}/account.

    1. Get the Regent sign-in client:
       curl -fsSO https://siwa.regents.sh/agent/siwa_agent.py
    2. Make your key if you have none. Keep an existing one; never show it.
       uv run siwa_agent.py keygen
    3. Pair with my code. Never repeat the code in a reply.
       uv run siwa_agent.py pair #{origin()} <CODE> --name "#{agent.name}" --harness #{agent.harness}
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

    1. Your person makes a pairing code on their Account page: #{origin()}/account. A code works once, for ten minutes.
    2. Follow the steps for your agent below, with that code.
    3. Your agent then shows on their Account page under its name.

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
