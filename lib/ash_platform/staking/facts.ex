defmodule AshPlatform.Staking.Facts do
  @moduledoc """
  The two Base readings a staking page shows, and the one shape they merge into.

  A protocol reading answers for the contract and a wallet reading answers for
  one account. They are taken at different blocks and neither waits for the
  other, so each carries the block it was read at and the page labels its
  figures with that block. Merging them never rewrites the other's block.

  The protocol reading also carries a stretch of history rather than a single
  moment: the seven days of recorded USDC end at the block it was read at and
  begin at `usdc_received_from_block`, so the window is always the chain's own
  and never the clock's.
  """

  @protocol_keys [
    :chain_id,
    :chain_label,
    :block_number,
    :block_hash,
    :read_at,
    :contract_address,
    :stake_token_address,
    :usdc_address,
    :paused,
    :total_staked_raw,
    :total_staked,
    :remaining_capacity_raw,
    :usdc_received_from_block,
    :usdc_received_7d_raw,
    :usdc_received_7d,
    :usdc_received_lifetime_raw,
    :usdc_received_lifetime,
    :regent_total_supply_raw,
    :regent_total_supply,
    :emission_apr_bps,
    :emission_apr_percent
  ]

  @wallet_keys [
    :wallet_block_number,
    :wallet_block_hash,
    :wallet_address,
    :wallet_token_balance_raw,
    :wallet_token_balance,
    :wallet_usdc_balance_raw,
    :wallet_usdc_balance,
    :wallet_stake_allowance_raw,
    :wallet_stake_balance_raw,
    :wallet_stake_balance,
    :wallet_claimable_usdc_raw,
    :wallet_claimable_usdc,
    :wallet_claimable_regent_raw,
    :wallet_claimable_regent,
    :wallet_funded_claimable_regent_raw,
    :wallet_funded_claimable_regent
  ]

  def protocol_keys, do: @protocol_keys
  def wallet_keys, do: @wallet_keys

  @doc "A wallet reading that found nothing, which is never a set of zero balances."
  def blank_wallet, do: Map.new(@wallet_keys, &{&1, nil})

  @doc "One page reading: this protocol reading with this wallet reading beside it."
  def merge(protocol, wallet) when is_map(protocol) and is_map(wallet),
    do: Map.merge(protocol, wallet)

  @doc "This page reading with a newly shared protocol reading in place of its own."
  def adopt_protocol(nil, protocol), do: merge(protocol, blank_wallet())
  def adopt_protocol(reading, protocol) when is_map(reading), do: Map.merge(reading, protocol)
end
