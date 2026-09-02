defmodule AshPlatform.Staking.ChainClient do
  @moduledoc """
  The two Base readings the staking pages take, kept apart on purpose.

  `protocol_snapshot/0` answers for the contract and is shared by every
  visitor. `wallet_snapshot/1` answers for one connected account and is never
  shared, never cached, and always taken at its own fresh block.
  """

  @callback protocol_snapshot() :: {:ok, map()} | {:error, atom()}
  @callback wallet_snapshot(String.t()) :: {:ok, map()} | {:error, atom()}
  @callback allowance(String.t(), non_neg_integer()) ::
              {:ok, :sufficient | :insufficient} | {:error, atom()}

  def module do
    Application.get_env(:ash_platform, :staking_chain_client, AshPlatform.Staking.RpcClient)
  end
end
