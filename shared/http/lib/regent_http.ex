defmodule RegentHttp do
  @moduledoc """
  Shared Req HTTP client conventions for Regent Elixir apps.

  Every request gets a default receive timeout and connect timeout, emits a
  `[:regent_http, :request]` telemetry event, and error formatting redacts
  bearer tokens, Stripe-style secret keys, Anthropic API keys, and authorization
  header values.
  """

  @default_receive_timeout 15_000
  @default_connect_options [timeout: 5_000]

  @doc """
  Performs an HTTP request with the shared timeout defaults.

  Accepts the same options as `Req.request/1`. `:receive_timeout` and
  `:connect_options` are filled in when absent.
  """
  @spec request(keyword()) :: {:ok, Req.Response.t()} | {:error, term()}
  def request(opts) when is_list(opts) do
    started_at = System.monotonic_time()
    normalized_opts = normalize_opts(opts)

    result =
      with {:ok, _started} <- Application.ensure_all_started(:req) do
        Req.request(normalized_opts)
      end

    :telemetry.execute(
      [:regent_http, :request],
      %{duration: System.monotonic_time() - started_at},
      %{
        method: normalized_opts[:method],
        host: request_host(normalized_opts[:url]),
        result: result_status(result)
      }
    )

    result
  end

  @doc "GET `url` via `request/1`."
  @spec get(String.t() | URI.t(), keyword()) :: {:ok, Req.Response.t()} | {:error, term()}
  def get(url, opts \\ []), do: request([method: :get, url: url] ++ opts)

  @doc "POST to `url` via `request/1`."
  @spec post(String.t() | URI.t(), keyword()) :: {:ok, Req.Response.t()} | {:error, term()}
  def post(url, opts \\ []), do: request([method: :post, url: url] ++ opts)

  @doc """
  Renders an error as a log-safe string with secrets redacted.
  """
  @spec format_error(term()) :: String.t()
  def format_error(%{__exception__: true} = error), do: error |> Exception.message() |> redact()
  def format_error({_kind, message}) when is_binary(message), do: redact(message)
  def format_error(error), do: error |> inspect() |> redact()

  @doc """
  Redacts bearer tokens, Stripe-style keys, Anthropic keys, and api-key/authorization header
  values from a binary. Non-binaries pass through unchanged.
  """
  @spec redact(term()) :: term()
  def redact(value) when is_binary(value) do
    value
    |> String.replace(~r/Bearer\s+[A-Za-z0-9._~+\/=-]+/i, "Bearer [redacted]")
    |> String.replace(~r/(sk|pk|rk)_(live|test)_[A-Za-z0-9_]+/, "\\1_\\2_[redacted]")
    |> String.replace(~r/sk-ant-[A-Za-z0-9_-]+/, "sk-ant-[redacted]")
    |> String.replace(~r/(x-api-key["':\s=>]+)[^,\]\}\s]+/i, "\\1[redacted]")
    |> String.replace(~r/(authorization["':\s=>]+)[^,\]\}]+/i, "\\1[redacted]")
  end

  def redact(value), do: value

  defp normalize_opts(opts) do
    opts
    |> Keyword.put_new(:receive_timeout, @default_receive_timeout)
    |> Keyword.put_new(:connect_options, @default_connect_options)
  end

  defp request_host(%URI{host: host}), do: host

  defp request_host(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) -> host
      _uri -> "unknown"
    end
  end

  defp request_host(_url), do: "unknown"

  defp result_status({:ok, %{status: status}}), do: status
  defp result_status({:error, _reason}), do: :error
end
