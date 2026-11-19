defmodule AgentEns.ERC8004.Fetcher do
  @moduledoc """
  Behaviour for fetching ERC-8004 registration payloads.
  """

  @callback fetch(String.t(), keyword()) :: {:ok, binary()} | {:error, term()}
end
