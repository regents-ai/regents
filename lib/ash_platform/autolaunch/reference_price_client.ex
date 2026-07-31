defmodule AshPlatform.Autolaunch.ReferencePriceClient do
  @moduledoc false

  require Logger

  @regent_token "0x6f89bca4ea5931edfcb09786267b251dee752b07"
  @default_url "https://api.geckoterminal.com/api/v2/networks/base/tokens/#{@regent_token}"

  def fetch_regent_usd do
    client =
      Application.get_env(
        :ash_platform,
        :autolaunch_buyback_reference_http_client,
        Req
      )

    url =
      Application.get_env(
        :ash_platform,
        :autolaunch_buyback_reference_url,
        @default_url
      )

    response =
      client.get(url,
        headers: [{"accept", "application/json"}],
        connect_options: [timeout: 3_000],
        pool_timeout: 3_000,
        receive_timeout: 8_000,
        retry: false
      )

    handle_response(response)
  rescue
    exception ->
      Logger.warning(
        "autolaunch buyback reference price failed category=exception " <>
          "exception=#{inspect(exception.__struct__)}"
      )

      {:error, {:exception, exception.__struct__}}
  end

  defp handle_response(
         {:ok,
          %{
            status: status,
            body: %{"data" => %{"attributes" => %{"price_usd" => price}}}
          }}
       )
       when status in 200..299 and is_binary(price) do
    case positive_decimal(price) do
      {:ok, parsed} ->
        {:ok, parsed}

      :error ->
        log_malformed_body()
    end
  end

  defp handle_response({:ok, %{status: status}})
       when is_integer(status) and status not in 200..299 do
    Logger.warning(
      "autolaunch buyback reference price failed category=http_status status=#{status}"
    )

    {:error, {:http_status, status}}
  end

  defp handle_response({:error, reason}) do
    if timeout?(reason) do
      Logger.warning("autolaunch buyback reference price failed category=timeout")
      {:error, :timeout}
    else
      Logger.warning("autolaunch buyback reference price failed category=request_error")
      {:error, :request_error}
    end
  end

  defp handle_response(_response), do: log_malformed_body()

  defp log_malformed_body do
    Logger.warning("autolaunch buyback reference price failed category=malformed_body")
    {:error, :malformed_body}
  end

  defp positive_decimal(value) do
    case Decimal.parse(value) do
      {price, ""} ->
        if Decimal.compare(price, 0) == :gt, do: {:ok, price}, else: :error

      _ ->
        :error
    end
  end

  defp timeout?(reason) when reason in [:timeout, :request_timeout], do: true
  defp timeout?(%{reason: reason}), do: timeout?(reason)
  defp timeout?(_reason), do: false
end
