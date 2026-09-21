defmodule AshPlatform.Staking.Supply do
  @moduledoc """
  How much REGENT is actually in circulation.

  The whole supply is one hundred billion REGENT. What circulates is that
  supply less the REGENT nobody can spend today, which is held in four places:

    * the Clanker vault, which releases on its own schedule
    * the protocol's own treasury
    * the Animata redeemer, which pays out over time
    * the staking contract's own reward inventory, which shrinks as it is claimed

  All four are counted from the chain at the block the rest of the reading was
  taken at. The vault and the redeemer hold tokens rather than answering about
  them, so both are read with the token's own `balanceOf`; the treasury is
  whichever address the staking contract names, and the inventory is the
  contract's own answer.
  """

  @clanker_vault "0x8e845ead15737bf71904a30bddd3aee76d6adf6c"
  @animata_redeemer "0x71065b775a590c43933F10c0055dc7d74AfAbb0e"

  @doc "The Clanker vault, whose REGENT releases on its own schedule."
  def clanker_vault, do: @clanker_vault

  @doc "The Animata redeemer, whose REGENT balance is not yet circulating."
  def animata_redeemer, do: @animata_redeemer

  @doc """
  The circulating REGENT for one reading, in atomic units.

  Every argument is an atomic amount read at the same block. A total that came
  out below what is held is nothing rather than a negative supply.
  """
  def circulating(total, vault, treasury, redeemer, reward_inventory)
      when is_integer(total) and is_integer(vault) and is_integer(treasury) and
             is_integer(redeemer) and is_integer(reward_inventory),
      do: max(total - vault - treasury - redeemer - reward_inventory, 0)
end
