defmodule Regents.Staking do
  @moduledoc "Canonical domain boundary for REGENT staking on Base."
  use Ash.Domain

  resources do
    resource Regents.Staking.ProtocolReading do
      define :get_protocol_reading, action: :read, get_by: [:id], not_found_error?: false
      define :current_protocol_reading, action: :current, get_by: [:id], not_found_error?: false
      define :record_protocol_reading, action: :record
      define :replace_protocol_reading, action: :replace
    end

    resource Regents.Staking.Snapshot do
      define :overview, action: :overview
      define :account, action: :account
      define :account_for_wallet, action: :account_for_wallet, args: [:expected_signer]
    end
  end

  # The Stake rules the page needs, owned here so the page and the steps it
  # builds can only ever answer the same way.
  defdelegate limit_refusal(snapshot, action, amount), to: Regents.Staking.Actions
  defdelegate spendable(snapshot, action), to: Regents.Staking.Actions
  defdelegate available_claims(snapshot), to: Regents.Staking.Actions
  defdelegate parse_amount(value), to: Regents.Staking.Actions
end
