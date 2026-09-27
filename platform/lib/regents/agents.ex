defmodule Regents.Agents do
  @moduledoc "Agents people pair with their accounts, and what those agents do."

  use Ash.Domain,
    otp_app: :regents

  resources do
    resource Regents.Agents.PairingCode do
      define :issue_pairing_code, action: :issue
    end

    resource Regents.Agents.PairedAgent do
      define :pair_agent, action: :pair, args: [:code, :wallet, :name, :harness]
      define :check_in_agent, action: :check_in, args: [:wallet]
      define :list_my_agents, action: :mine
      define :get_my_agent, action: :mine_by_id, args: [:id], not_found_error?: false
      define :change_agent_harness, action: :change_harness, args: [:harness]
      define :unpair_agent, action: :unpair
    end
  end
end
