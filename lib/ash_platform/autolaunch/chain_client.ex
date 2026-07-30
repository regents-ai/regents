defmodule AshPlatform.Autolaunch.ChainClient do
  @moduledoc false

  @callback confirm(map(), String.t(), String.t() | nil) :: {:ok, map()} | {:error, atom()}
  @callback approval_status(map(), String.t()) ::
              {:ok, :success | :reverted | :pending} | {:error, atom()}

  def module do
    Application.get_env(
      :ash_platform,
      :autolaunch_bid_chain_client,
      AshPlatform.Autolaunch.RpcClient
    )
  end
end
