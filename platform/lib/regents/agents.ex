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
      define :read_credits_balance, action: :credits_balance
      define :read_credits_budget, action: :credits_budget
      define :read_credits_history, action: :credits_history, args: [{:optional, :after}]
      define :read_points_summary, action: :points_summary
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
    regents_credits_balance:
      {:credits_balance, "Read shared Credits balance",
       "Read your person's Credits balance: available, given, purchased and held. Changes nothing."},
    regents_credits_budget:
      {:credits_budget, "Read my effective spending budget",
       "Read what this pairing may spend of your person's Credits, which sites it may spend on and what your person's agents spent in the last 24 hours. Does not change a grant or spend."},
    regents_credits_history:
      {:credits_history, "Read shared Credits history",
       "Read your person's Credits history, newest first. Send {} first, then pass pagination.next_cursor unchanged as after; leave after out when it is null. Changes nothing."},
    regents_points_summary:
      {:points_summary, "Read shared Points summary",
       "Read your person's Points balance, recent entries, pending count and remaining daily allowances. Awards no Points and changes nothing."}
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
