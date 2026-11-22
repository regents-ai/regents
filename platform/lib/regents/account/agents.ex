defmodule Regents.Account.Agents do
  @moduledoc """
  The site's reads of the agent pairing every Regent site shares (`RegentAgents`),
  and the connected-app identity tools offered at `/mcp`.
  """
  use Ash.Domain, otp_app: :regents, extensions: [AshAi]

  resources do
    resource Regents.Account.Agents.Pairing do
      define :pairings_by_wallets, action: :by_wallets, args: [:wallets]
    end

    resource Regents.Account.Agents.PairedPersonWallet
    resource Regents.Account.Agents.Connection
  end

  tools do
    tool :register_identity, Regents.Account.Agents.Connection, :register_identity do
      title("Prepare identity")

      description "Prepares this connected app's persistent Regents identity for the signed-in account."

      annotations(
        read_only_hint: false,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :get_identity, Regents.Account.Agents.Connection, :get_identity do
      title("Identity status")
      description "Reads whether this connected app's persistent Regents identity is paired."

      annotations(
        read_only_hint: true,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :pair_identity, Regents.Account.Agents.Connection, :pair_identity do
      title("Pair identity")
      description "Pairs this connected app's identity with a one-time code from Pair New Agent."

      annotations(
        read_only_hint: false,
        idempotent_hint: false,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :check_in, Regents.Account.Agents.Connection, :check_in do
      title("Check in")
      description "Checks in as the paired identity and reads the account it is paired with."

      annotations(
        read_only_hint: false,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end
  end
end
