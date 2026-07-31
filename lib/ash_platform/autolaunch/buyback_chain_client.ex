defmodule AshPlatform.Autolaunch.BuybackChainClient do
  @moduledoc false

  @callback confirm(map(), String.t()) :: {:ok, map()} | {:error, atom()}

  def module do
    Application.get_env(
      :ash_platform,
      :autolaunch_buyback_chain_client,
      AshPlatform.Autolaunch.BuybackRpcClient
    )
  end
end
