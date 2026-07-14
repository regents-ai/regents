defmodule AshPlatform.Staking.ChainClient do
  @moduledoc false

  @callback overview(String.t() | nil) :: {:ok, map()} | {:error, atom()}
  @callback confirm(map(), String.t(), String.t() | nil) :: {:ok, map()} | {:error, atom()}
  @callback approval_status(map(), String.t()) ::
              {:ok, :success | :reverted | :pending} | {:error, atom()}

  def module do
    Application.get_env(:ash_platform, :staking_chain_client, AshPlatform.Staking.RpcClient)
  end
end
