defmodule AgentEns.Internal.RPC do
  @moduledoc false

  # Failed calls return {:error, {:rpc_call_failed, %{to: to, reason: reason}}}
  # so callers always know which contract the failing call targeted.

  @type call_error :: {:rpc_call_failed, %{to: String.t(), reason: term()}}

  @callback eth_call(String.t(), String.t(), String.t()) ::
              {:ok, String.t()} | {:error, call_error()}

  @spec eth_call(String.t(), String.t(), String.t()) ::
          {:ok, String.t()} | {:error, call_error()}
  def eth_call(rpc_url, to, data) do
    to = String.downcase(to)

    case Siwa.RPCClient.call(rpc_url, "eth_call", [%{"to" => to, "data" => data}, "latest"]) do
      {:ok, result} when is_binary(result) ->
        {:ok, result}

      {:ok, result} ->
        {:error, {:rpc_call_failed, %{to: to, reason: {:unexpected_body, result}}}}

      {:error, reason} ->
        {:error, {:rpc_call_failed, %{to: to, reason: reason}}}
    end
  end
end
