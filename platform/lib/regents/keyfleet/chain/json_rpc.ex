defmodule Regents.Keyfleet.Chain.JsonRpc do
  @moduledoc """
  One JSON-RPC request to Base through the site's one Base read endpoint
  (`:base_read_rpc_url`), for the fleet reader.

  It logs nothing, so the endpoint's address never reaches a log; each caller
  says what failed in its own words.
  """

  @timeout 20_000

  @doc """
  Sends `method` with `params` and returns `{:ok, result}`,
  `{:error, {:rpc_error, %{code: code, message: message, data: data}}}` when
  the node answered with an error, or `{:error, {:unavailable, detail}}` when
  it did not answer, where `detail` holds the HTTP `:status` or the
  transport's `:reason`.
  """
  def request(method, params) do
    case Req.post(Application.fetch_env!(:regents, :base_read_rpc_url),
           json: %{jsonrpc: "2.0", id: 1, method: method, params: params},
           receive_timeout: @timeout,
           retry: false
         ) do
      {:ok, %{status: 200, body: %{"result" => result}}} ->
        {:ok, result}

      {:ok, %{status: 200, body: %{"error" => %{} = error}}} ->
        {:error,
         {:rpc_error, %{code: error["code"], message: error["message"], data: error["data"]}}}

      {:ok, %{status: status}} ->
        {:error, {:unavailable, %{status: status}}}

      {:error, reason} ->
        {:error, {:unavailable, %{reason: reason}}}
    end
  end

  @doc """
  Whether a node error says the contract refused the call: error code 3, or
  a message saying execution reverted, in any case.
  """
  def reverted?(%{code: 3}), do: true

  def reverted?(%{message: message}) when is_binary(message),
    do: message |> String.downcase() |> String.contains?("execution reverted")

  def reverted?(_error), do: false
end
