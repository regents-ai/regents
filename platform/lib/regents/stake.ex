defmodule Regents.Stake do
  @moduledoc "Canonical domain boundary for REGENT staking on Base."
  use Ash.Domain

  resources do
    resource Regents.Stake.ProtocolReading do
      define :get_protocol_reading, action: :read, get_by: [:id], not_found_error?: false
      define :current_protocol_reading, action: :current, get_by: [:id], not_found_error?: false
      define :record_protocol_reading, action: :record
      define :replace_protocol_reading, action: :replace
    end

    resource Regents.Stake.Snapshot do
      define :overview, action: :overview
      define :account, action: :account
      define :account_for_wallet, action: :account_for_wallet, args: [:expected_signer]
    end
  end

  # The Stake rules the page needs, owned here so the page and the steps it
  # builds can only ever answer the same way.
  defdelegate limit_refusal(snapshot, action, amount), to: Regents.Stake.Actions
  defdelegate spendable(snapshot, action), to: Regents.Stake.Actions
  defdelegate available_claims(snapshot), to: Regents.Stake.Actions
  defdelegate parse_amount(value), to: Regents.Stake.Actions
end
