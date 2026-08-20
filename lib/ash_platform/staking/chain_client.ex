defmodule AshPlatform.Staking.ChainClient do
  @moduledoc false

  @type outcome :: :confirmed | :unverified | :reverted | :pending

  @callback overview(String.t() | nil) :: {:ok, map()} | {:error, atom()}
  @callback confirm(map(), String.t()) :: {:ok, map()} | {:error, atom()}
  @callback approval_status(map(), String.t()) :: {:ok, outcome()} | {:error, atom()}
  @callback approval_current(map()) :: :ok | {:error, atom()}

  def module do
    Application.get_env(:ash_platform, :staking_chain_client, AshPlatform.Staking.RpcClient)
  end
end
