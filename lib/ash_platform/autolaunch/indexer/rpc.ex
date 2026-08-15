defmodule AshPlatform.Autolaunch.Indexer.Rpc do
  @moduledoc """
  The indexer's own JSON-RPC transport, and the redaction boundary around it.

  The endpoint is dedicated to this indexer and separate from the simple-read
  RPC. It never reaches a result, an error, a row or a log line: a failure is
  reported as the method plus a small error class, so a URL carrying a provider
  key cannot escape through a crash report or a captured log.

  A reply counts only as this exchange's own answer: JSON-RPC 2.0, the id that
  was sent, and a result member. Nothing is retried and nothing falls back, so
  one request costs at most one bounded deadline.
  """

  require Logger

  @id 1
  @pool_timeout 3_000
  @connect_timeout 3_000
  @receive_timeout 8_000

  @doc """
  The conservative wall-clock ceiling one request can occupy.

  A single call can spend each of its three deadlines in full — waiting for a
  pool checkout, connecting, then waiting for the response — and never repeats,
  so their sum bounds it.
  """
  @spec max_request_ms() :: pos_integer()
  def max_request_ms, do: @pool_timeout + @connect_timeout + @receive_timeout

  @spec request(String.t(), list()) :: {:ok, term()} | {:error, :chain_unavailable}
  def request(method, params) do
    case post(method, params) do
      {:ok, response} -> answered(method, response)
      {:error, reason} -> failed(method, class(reason))
    end
  rescue
    error -> failed(method, class(error))
  end

  defp post(method, params) do
    client().post(url(),
      json: %{jsonrpc: "2.0", id: @id, method: method, params: params},
      connect_options: [timeout: @connect_timeout],
      pool_timeout: @pool_timeout,
      receive_timeout: @receive_timeout,
      retry: false
    )
  end

  defp answered(_method, %{
         status: 200,
         body: %{"jsonrpc" => "2.0", "id" => @id, "result" => result}
       }),
       do: {:ok, result}

  # A 200 that is not this exchange's own result is an RPC-level failure; any
  # other status is an HTTP one. Neither body is ever read into a log line.
  defp answered(method, %{status: 200}), do: failed(method, :rpc)
  defp answered(method, _response), do: failed(method, :http)

  defp failed(method, class) do
    Logger.warning(
      "autolaunch indexer chain read failed #{inspect(%{method: method, class: class})}"
    )

    {:error, :chain_unavailable}
  end

  defp class(%Req.TransportError{reason: reason}) when reason in [:timeout, :connect_timeout],
    do: :timeout

  defp class(_reason), do: :transport

  defp client, do: Application.get_env(:ash_platform, :autolaunch_indexer_http_client, Req)
  defp url, do: Application.fetch_env!(:ash_platform, :autolaunch_indexer_rpc_url)
end
