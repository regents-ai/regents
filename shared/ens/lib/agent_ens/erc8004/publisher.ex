defmodule AgentEns.ERC8004.Publisher do
  @moduledoc """
  Behaviour for publishing updated ERC-8004 registration payloads.
  """

  @callback publish(binary(), keyword()) :: {:ok, String.t()} | {:error, term()}
end
