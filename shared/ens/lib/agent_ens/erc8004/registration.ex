defmodule AgentEns.ERC8004.Registration do
  @moduledoc """
  Helpers for reading, patching, and publishing ERC-8004 registration files.
  """

  alias AgentEns.Error
  alias AgentEns.ERC8004.Fetcher
  alias AgentEns.ERC8004.Publisher

  defmodule DefaultFetcher do
    @behaviour Fetcher

    @http_timeout_ms 5_000

    @impl true
    def fetch(uri, opts \\ []) when is_binary(uri) do
      case URI.parse(uri) do
        %URI{scheme: "data"} ->
          AgentEns.ERC8004.Registration.decode_data_uri(uri)

        %URI{scheme: "http"} ->
          fetch_http(uri, opts)

        %URI{scheme: "https"} ->
          fetch_http(uri, opts)

        %URI{scheme: "ipfs", host: cid, path: path} ->
          gateway = Keyword.get(opts, :ipfs_gateway, "https://ipfs.io/ipfs")
          suffix = if is_binary(path), do: path, else: ""
          fetch_http("#{String.trim_trailing(gateway, "/")}/#{cid}#{suffix}", opts)

        %URI{scheme: nil} ->
          {:error, {:unsupported_uri_scheme, uri}}

        %URI{scheme: scheme} ->
          {:error, {:unsupported_uri_scheme, scheme}}
      end
    end

    defp fetch_http(url, _opts) do
      case Req.get(
             url: url,
             headers: [{"accept", "application/json, text/plain;q=0.9, */*;q=0.1"}],
             receive_timeout: @http_timeout_ms,
             connect_options: [timeout: @http_timeout_ms],
             retry: false
           ) do
        {:ok, %{status: status, body: body}} when status in 200..299 ->
          cond do
            is_binary(body) -> {:ok, body}
            is_map(body) -> {:ok, Jason.encode!(body)}
            true -> {:error, {:unexpected_body, body}}
          end

        {:ok, %{status: status, body: body}} ->
          {:error, {:http_error, status, body}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defmodule DataUriPublisher do
    @behaviour Publisher

    @impl true
    def publish(binary, _opts \\ []) when is_binary(binary) do
      encoded = URI.encode_www_form(binary)
      {:ok, "data:application/json,#{encoded}"}
    end
  end

  @canonical_type "https://eips.ethereum.org/EIPS/eip-8004#registration-v1"

  @spec fetch(String.t(), module(), keyword()) :: {:ok, binary()} | {:error, Error.t()}
  def fetch(agent_uri, fetcher \\ DefaultFetcher, opts \\ []) when is_binary(agent_uri) do
    case fetcher.fetch(agent_uri, opts) do
      {:ok, payload} when is_binary(payload) ->
        {:ok, payload}

      {:error, reason} ->
        {:error, Error.new({:erc8004_registration_fetch_failed, reason})}
    end
  end

  @spec parse_registration(binary()) :: {:ok, map()} | {:error, Error.t()}
  def parse_registration(payload) when is_binary(payload) do
    with {:ok, decoded} <- maybe_decode_data_uri(payload),
         {:ok, parsed} <- Jason.decode(decoded) do
      case parsed do
        %{} = map -> {:ok, map}
        other -> {:error, Error.new({:erc8004_registration_parse_failed, other})}
      end
    else
      {:error, %Error{} = error} -> {:error, error}
      {:error, reason} -> {:error, Error.new({:erc8004_registration_parse_failed, reason})}
    end
  end

  @spec serialize_registration(map()) :: {:ok, binary()} | {:error, Error.t()}
  def serialize_registration(%{} = registration) do
    case Jason.encode(registration) do
      {:ok, json} -> {:ok, json}
      {:error, reason} -> {:error, Error.new({:erc8004_registration_parse_failed, reason})}
    end
  end

  @spec upsert_ens_service(map(), String.t()) :: map()
  def upsert_ens_service(%{} = registration, ens_name)
      when is_binary(ens_name) and ens_name != "" do
    services =
      registration
      |> existing_services()
      |> Enum.reject(&(service_name(&1) == "ens"))
      |> Kernel.++([%{"name" => "ENS", "endpoint" => ens_name, "version" => "v1"}])

    registration
    |> Map.put("type", Map.get(registration, "type", @canonical_type))
    |> Map.put("services", services)
  end

  @spec remove_ens_service(map()) :: map()
  def remove_ens_service(%{} = registration) do
    services =
      registration
      |> existing_services()
      |> Enum.reject(&(service_name(&1) == "ens"))

    registration
    |> Map.put("type", Map.get(registration, "type", @canonical_type))
    |> Map.put("services", services)
  end

  @spec prepare_updated_registration(map()) ::
          {:ok, %{new_uri: String.t(), new_registration: map(), changed?: boolean()}}
          | {:error, Error.t()}
  def prepare_updated_registration(params) when is_map(params) do
    params = normalize_prepare_params(params)

    with value when is_binary(value) and value != "" <-
           params.current_agent_uri || :missing_agent_uri,
         ens when is_binary(ens) and ens != "" <- params.ens_name || :missing_ens_name,
         {:ok, payload} <- fetch(value, params.fetcher, params.opts),
         {:ok, registration} <- parse_registration(payload),
         updated = upsert_ens_service(registration, ens),
         changed? <- updated != registration,
         {:ok, serialized} <- serialize_registration(updated),
         {:ok, uri} <- publish(params.publisher, serialized, params.opts) do
      {:ok, %{new_uri: uri, new_registration: updated, changed?: changed?}}
    else
      :missing_agent_uri ->
        {:error, Error.new({:missing_required_input, "current_agent_uri"})}

      :missing_ens_name ->
        {:error, Error.new({:missing_required_input, "ens_name"})}

      {:error, %Error{} = error} ->
        {:error, error}

      other ->
        {:error, Error.new({:unexpected_state, other})}
    end
  end

  @spec prepare_cleared_registration(map()) ::
          {:ok, %{new_uri: String.t(), new_registration: map(), changed?: boolean()}}
          | {:error, Error.t()}
  def prepare_cleared_registration(params) when is_map(params) do
    params = normalize_prepare_params(params)

    with value when is_binary(value) and value != "" <-
           params.current_agent_uri || :missing_agent_uri,
         {:ok, payload} <- fetch(value, params.fetcher, params.opts),
         {:ok, registration} <- parse_registration(payload),
         updated = remove_ens_service(registration),
         changed? <- updated != registration,
         {:ok, serialized} <- serialize_registration(updated),
         {:ok, uri} <- publish(params.publisher, serialized, params.opts) do
      {:ok, %{new_uri: uri, new_registration: updated, changed?: changed?}}
    else
      :missing_agent_uri ->
        {:error, Error.new({:missing_required_input, "current_agent_uri"})}

      {:error, %Error{} = error} ->
        {:error, error}

      other ->
        {:error, Error.new({:unexpected_state, other})}
    end
  end

  @spec decode_data_uri(String.t()) :: {:ok, binary()} | {:error, term()}
  def decode_data_uri("data:" <> rest) do
    case String.split(rest, ",", parts: 2) do
      [meta, encoded] ->
        {content_type, base64?} = parse_data_uri_meta(meta)

        cond do
          not supported_content_type?(content_type) ->
            {:error, {:unsupported_content_type, meta}}

          base64? ->
            Base.decode64(encoded)

          true ->
            {:ok, URI.decode_www_form(encoded)}
        end

      _ ->
        {:error, :invalid_data_uri}
    end
  end

  def decode_data_uri(value), do: {:error, {:invalid_data_uri, value}}

  defp normalize_prepare_params(params) do
    %{
      current_agent_uri: Map.get(params, :current_agent_uri),
      ens_name: Map.get(params, :ens_name),
      fetcher: Map.get(params, :fetcher) || DefaultFetcher,
      publisher: Map.get(params, :publisher) || DataUriPublisher,
      opts: Map.get(params, :opts) || []
    }
  end

  defp publish(publisher, serialized, opts) do
    case publisher.publish(serialized, opts) do
      {:ok, uri} when is_binary(uri) and uri != "" -> {:ok, uri}
      {:error, reason} -> {:error, Error.new({:publisher_failed, reason})}
      other -> {:error, Error.new({:publisher_failed, other})}
    end
  end

  defp maybe_decode_data_uri("data:" <> _ = payload) do
    case decode_data_uri(payload) do
      {:ok, binary} -> {:ok, binary}
      {:error, reason} -> {:error, Error.new({:invalid_data_uri, reason})}
    end
  end

  defp maybe_decode_data_uri(payload), do: {:ok, payload}

  defp existing_services(registration) do
    case Map.get(registration, "services") do
      list when is_list(list) -> Enum.filter(list, &is_map/1)
      _ -> []
    end
  end

  defp service_name(service) do
    service
    |> Map.get("name", "")
    |> to_string()
    |> String.downcase()
  end

  defp parse_data_uri_meta(meta) do
    segments = String.split(meta, ";", trim: true)
    base64? = Enum.any?(segments, &(&1 == "base64"))

    content_type =
      case segments do
        [] -> ""
        [first | _rest] when first == "base64" -> ""
        [first | _rest] -> first
      end

    {content_type, base64?}
  end

  defp supported_content_type?(content_type), do: content_type in ["", "application/json"]
end
