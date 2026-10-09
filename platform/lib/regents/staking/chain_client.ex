defmodule Regents.Staking.ChainClient do
  @moduledoc """
  The Base readings the staking pages take, kept apart on purpose.

  `protocol_snapshot/1` advances the retained public contract history for the
  shared job. `protocol_snapshot/0` is a stateless diagnostic read.
  `wallet_snapshot/1` answers for one connected account and is never
  shared, never cached, and always taken at its own fresh block.
  """

  @callback protocol_snapshot() :: {:ok, map()} | {:error, atom()}
  @callback protocol_snapshot(map() | nil) :: {:ok, map(), map()} | {:error, atom()}
  @optional_callbacks protocol_snapshot: 0
  @callback wallet_snapshot(String.t()) :: {:ok, map()} | {:error, atom()}

  def module do
    Application.get_env(:regents, :staking_chain_client, Regents.Staking.RpcClient)
  end
end
