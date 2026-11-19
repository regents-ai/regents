defmodule RegentPoints.ChainClient do
  @moduledoc "Host callback for Base JSON-RPC reads. The host owns the endpoint, its key and its limits."
  @callback rpc(%{chain_id: pos_integer()}, method :: String.t(), params :: list()) ::
              {:ok, term()} | {:error, term()}
end
