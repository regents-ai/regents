defmodule Regents.Account.Agents do
  @moduledoc """
  The site's reads of the agent pairing every Regent site shares (`RegentAgents`).
  """
  use Ash.Domain

  resources do
    resource Regents.Account.Agents.Pairing do
      define :pairings_by_wallets, action: :by_wallets, args: [:wallets]
    end
  end
end
