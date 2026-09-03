defmodule AshPlatform.Staking.Supply do
  @moduledoc """
  How much REGENT is actually in circulation.

  The whole supply is one hundred billion REGENT. What circulates is that
  supply less the REGENT nobody can spend today, which is held in four places:

    * the Clanker vault, which releases on its own schedule
    * the protocol's own treasury
    * the Animata redeemer, which pays out over time
    * the staking contract's own reward inventory, which shrinks as it is claimed

  Three of the four are counted from the chain at the block the rest of the
  reading was taken at. The vault is the exception: its address is not
  published to this app, so the founder's figure of forty billion stands for it
  until it is. That figure is written once, here.
  """

  @atomic Integer.pow(10, 18)

  @clanker_vault 40_000_000_000 * @atomic

  # The contract REGENT is redeemed out of. It holds tokens rather than
  # answering about them, so it is read with the token's own `balanceOf`.
  @animata_redeemer "0x71065b775a590c43933F10c0055dc7d74AfAbb0e"

  @doc "The Animata redeemer, whose REGENT balance is not yet circulating."
  def animata_redeemer, do: @animata_redeemer

  @doc "The Clanker vault's REGENT, in the token's own eighteen-decimal units."
  def clanker_vault_atomic, do: @clanker_vault

  @doc """
  The circulating REGENT for one reading, in atomic units.

  Every argument is an atomic amount read at the same block. A total that came
  out below what is held is nothing rather than a negative supply.
  """
  def circulating(total, treasury, redeemer, reward_inventory)
      when is_integer(total) and is_integer(treasury) and is_integer(redeemer) and
             is_integer(reward_inventory),
      do: max(total - @clanker_vault - treasury - redeemer - reward_inventory, 0)
end
