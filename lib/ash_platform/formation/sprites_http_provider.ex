defmodule AshPlatform.Formation.SpritesHttpProvider do
  @moduledoc false
  @behaviour AshPlatform.Formation.SpriteProvider

  @impl true
  def create(sprite_name) do
    with {:ok, config} <- config(),
         {:ok, response} <-
           Req.post(
             config.base_url <> "/v1/sprites",
             request_options(config,
               json: %{
                 name: sprite_name,
                 wait_for_capacity: false,
                 url_settings: %{auth: "sprite"}
               }
             )
           ) do
      case response.status do
        201 -> normalize_sprite(response.body)
        400 -> get(sprite_name)
        401 -> {:error, :unauthorized}
        status when status >= 500 -> {:error, :provider_unavailable}
        _status -> {:error, :provider_rejected}
      end
    else
      {:error, %Req.TransportError{}} -> {:error, :provider_unavailable}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def get(sprite_name) do
    with {:ok, config} <- config(),
         {:ok, response} <-
           Req.get(
             config.base_url <> "/v1/sprites/" <> URI.encode(sprite_name),
             request_options(config)
           ) do
      case response.status do
        200 -> normalize_sprite(response.body)
        401 -> {:error, :unauthorized}
        404 -> {:error, :not_found}
        status when status >= 500 -> {:error, :provider_unavailable}
        _status -> {:error, :provider_rejected}
      end
    else
      {:error, %Req.TransportError{}} -> {:error, :provider_unavailable}
      {:error, reason} -> {:error, reason}
    end
  end

  defp config do
    config = Application.fetch_env!(:ash_platform, :sprites)
    token = config[:token]
    base_url = config[:base_url]

    if present?(token) and valid_base_url?(base_url) do
      {:ok, %{token: token, base_url: String.trim_trailing(base_url, "/")}}
    else
      {:error, :not_configured}
    end
  end

  defp request_options(config, options \\ []) do
    [auth: {:bearer, config.token}, receive_timeout: 10_000]
    |> Keyword.merge(Application.get_env(:ash_platform, :sprites_req_options, []))
    |> Keyword.merge(options)
  end

  defp normalize_sprite(%{
         "id" => provider_sprite_id,
         "name" => sprite_name,
         "url" => url,
         "status" => provider_status
       })
       when is_binary(provider_sprite_id) and is_binary(sprite_name) and is_binary(url) and
              is_binary(provider_status) do
    with true <- present?(provider_sprite_id),
         true <- valid_sprite_name?(sprite_name),
         true <- valid_sprite_url?(url),
         true <- present?(provider_status) do
      {:ok,
       %{
         provider_sprite_id: provider_sprite_id,
         sprite_name: sprite_name,
         url: url,
         provider_status: provider_status
       }}
    else
      _ -> {:error, :invalid_provider_response}
    end
  end

  defp normalize_sprite(_body), do: {:error, :invalid_provider_response}

  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  defp valid_base_url?(value) do
    case URI.parse(value || "") do
      %URI{scheme: "https", host: host} when is_binary(host) -> host != ""
      _uri -> false
    end
  end

  defp valid_sprite_name?(name), do: Regex.match?(~r/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/, name)

  defp valid_sprite_url?(url) do
    case URI.parse(url) do
      %URI{scheme: "https", host: host} when is_binary(host) -> host != ""
      _uri -> false
    end
  end
end
