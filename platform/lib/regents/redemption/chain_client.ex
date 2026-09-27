defmodule Regents.Redemption.ChainClient do
  @moduledoc false

  @callback overview(String.t() | nil, String.t() | nil, integer() | nil) ::
              {:ok, map()} | {:error, atom()}

  def module do
    Application.get_env(:regents, :redemption_chain_client, Regents.Redemption.RpcClient)
  end
end
