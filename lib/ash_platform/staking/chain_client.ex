defmodule AshPlatform.Staking.ChainClient do
  @moduledoc false

  @callback overview(String.t() | nil) :: {:ok, map()} | {:error, atom()}
  @callback allowance(String.t(), non_neg_integer()) ::
              {:ok, :sufficient | :insufficient} | {:error, atom()}

  def module do
    Application.get_env(:ash_platform, :staking_chain_client, AshPlatform.Staking.RpcClient)
  end
end
