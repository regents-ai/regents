defmodule AshPlatform.Redemption.ChainClient do
  @moduledoc false

  @callback overview(String.t() | nil, String.t() | nil, integer() | nil) ::
              {:ok, map()} | {:error, atom()}

  def module do
    Application.get_env(:ash_platform, :redemption_chain_client, AshPlatform.Redemption.RpcClient)
  end
end
