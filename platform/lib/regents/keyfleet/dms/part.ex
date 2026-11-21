defmodule Regents.Keyfleet.Dms.Part do
  @moduledoc """
  One part of a direct message beside its words, in the shape agents already
  pass each other (A2A message parts), always with string keys:

    * `%{"kind" => "text", "text" => text}`: more words, up to 1,000
      characters.
    * `%{"kind" => "data", "data" => object}`: a small JSON object, up to 2,048
      bytes written out.
    * `%{"kind" => "link", "url" => url}`, with an optional `"name"`: an https
      address, which is how a message carries a file.

  Anything else, or any other key, is refused.
  """
  use Ash.Type

  @max_text 1_000
  @max_data 2_048
  @max_url 2_048
  @max_name 200

  @impl true
  def storage_type(_constraints), do: :map

  @impl true
  def cast_input(nil, _constraints), do: {:ok, nil}
  def cast_input(part, _constraints) when is_map(part), do: part(part)
  def cast_input(_part, _constraints), do: :error

  @impl true
  def cast_stored(nil, _constraints), do: {:ok, nil}
  def cast_stored(part, _constraints) when is_map(part), do: {:ok, part}
  def cast_stored(_part, _constraints), do: :error

  @impl true
  def dump_to_native(nil, _constraints), do: {:ok, nil}
  def dump_to_native(part, _constraints) when is_map(part), do: {:ok, part}
  def dump_to_native(_part, _constraints), do: :error

  defp part(%{"kind" => "text", "text" => text} = part)
       when map_size(part) == 2 and is_binary(text) do
    if String.length(text) in 1..@max_text,
      do: {:ok, part},
      else: {:error, message: "a text part has 1 to #{@max_text} characters"}
  end

  defp part(%{"kind" => "data", "data" => data} = part)
       when map_size(part) == 2 and is_map(data) do
    case Jason.encode(data) do
      {:ok, json} when byte_size(json) <= @max_data ->
        {:ok, %{part | "data" => Jason.decode!(json)}}

      {:ok, _json} ->
        {:error, message: "a data part is at most #{@max_data} bytes"}

      {:error, _error} ->
        {:error, message: "a data part is a JSON object"}
    end
  end

  defp part(%{"kind" => "link", "url" => url} = part) when is_binary(url) do
    with :ok <- only_keys(part, ["kind", "url", "name"]),
         :ok <- https(url),
         :ok <- name(Map.get(part, "name")) do
      {:ok, part}
    end
  end

  defp part(_part),
    do: {:error, message: "a part is a text, data or link part"}

  defp only_keys(part, keys) do
    if Map.keys(part) -- keys == [],
      do: :ok,
      else: {:error, message: "a link part has only kind, url and name"}
  end

  defp https(url) do
    case URI.new(url) do
      {:ok, %URI{scheme: "https", host: host}}
      when is_binary(host) and host != "" and byte_size(url) <= @max_url ->
        :ok

      _not_https ->
        {:error, message: "a link is an https address of at most #{@max_url} characters"}
    end
  end

  defp name(nil), do: :ok

  defp name(name) when is_binary(name) do
    if String.length(name) in 1..@max_name,
      do: :ok,
      else: {:error, message: "a link's name has 1 to #{@max_name} characters"}
  end

  defp name(_name), do: {:error, message: "a link's name is text"}
end
