defmodule Regents.Agents do
  @moduledoc """
  What an agent runs here beyond pairing (`RegentAgents`): a connected app's one
  Regents identity (`Regents.Agents.Connection`) and a paired agent's private
  reads of its person's account (`Regents.Agents.AccountReads`), which the agent API and
  the hosted MCP server both run.
  """

  use Ash.Domain, extensions: [AshAi]

  resources do
    resource Regents.Agents.Connection

    resource Regents.Agents.AccountReads do
      define :read_account, action: :account
      define :read_points, action: :points
    end
  end

  # The hosted MCP server's identity tools, for an app a person connected to their
  # account here, with the titles, words and hints every Regent site gives them.
  @identity Map.new(RegentMCPAgents.Tools.list(), &{&1.name, &1})

  # A paired agent's reads, each named after the browser tool that makes the same
  # read with a fresh signature (`priv/tool_manifest.json`).
  @reads [
    regents_account:
      {:account, "Read the paired account",
       "Read your person's display name and ENS name, with your pairing ID. Changes nothing."},
    account_points:
      {:points, "Read Points",
       "Read your person's Points, what they earned today and yesterday, their place, the actions still open, daily limits, the leaderboard by name or wallet and recent entries, each saying who earned it and whether it counted. Points are decimal text, such as \"12.5\". Changes nothing."}
  ]

  tools do
    for name <- RegentMCPAgents.Tools.names() do
      %{title: title, description: description, annotations: hints} = @identity[name]
      name = String.to_atom(name)

      tool name, Regents.Agents.Connection, name do
        title(title)
        description description

        annotations(
          read_only_hint: hints.readOnlyHint,
          idempotent_hint: hints.idempotentHint,
          destructive_hint: hints.destructiveHint,
          open_world_hint: hints.openWorldHint
        )
      end
    end

    for {name, {action, title, description}} <- @reads do
      tool name, Regents.Agents.AccountReads, action do
        title(title)
        description description

        annotations(
          read_only_hint: true,
          idempotent_hint: true,
          destructive_hint: false,
          open_world_hint: false
        )
      end
    end
  end
end
