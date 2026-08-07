defmodule AshPlatform.Techtree.PublicationInput do
  @moduledoc false

  @string_fields ~w(
    regent_id
    tree_id
    kind
    title
    summary
    payload_hash
    idempotency_key
    manifest_digest
    manifest_cid
    manifest_hash
    manifest_uri
  )
  @allowed_keys @string_fields ++ ["lineage"]

  @blank_ranges [
    {0x0009, 0x000D},
    {0x0020, 0x0020},
    {0x0085, 0x0085},
    {0x00A0, 0x00A0},
    {0x1680, 0x1680},
    {0x2000, 0x200A},
    {0x2028, 0x2028},
    {0x2029, 0x2029},
    {0x202F, 0x202F},
    {0x205F, 0x205F},
    {0x3000, 0x3000}
  ]

  @blank_codepoints for {first, last} <- @blank_ranges,
                        codepoint <- first..last,
                        do: codepoint

  @blank_codepoint_set MapSet.new(@blank_codepoints)

  @idempotency_key_pattern (
                             escape = fn codepoint ->
                               codepoint
                               |> Integer.to_string(16)
                               |> String.upcase()
                               |> String.pad_leading(4, "0")
                               |> then(&("\\u" <> &1))
                             end

                             encoded_ranges =
                               Enum.map_join(@blank_ranges, fn
                                 {codepoint, codepoint} ->
                                   escape.(codepoint)

                                 {first, last} ->
                                   escape.(first) <> "-" <> escape.(last)
                               end)

                             "[^" <> encoded_ranges <> "]"
                           )

  def string_fields, do: @string_fields
  def allowed_keys, do: @allowed_keys
  def idempotency_key_pattern, do: @idempotency_key_pattern

  def normalize(params) when is_map(params) do
    with :ok <- allow_keys(params) do
      {:ok,
       Enum.reduce(@string_fields, params, fn field, params ->
         Map.update(params, field, nil, &normalize_string/1)
       end)}
    end
  end

  def nonblank?(value) when is_binary(value) do
    String.valid?(value) and not is_nil(normalize_string(value))
  end

  def nonblank?(_value), do: false

  defp normalize_string(value) when is_binary(value) do
    if String.valid?(value) do
      case trim(value) do
        "" -> nil
        trimmed -> trimmed
      end
    else
      value
    end
  end

  defp normalize_string(value), do: value

  defp trim(value) do
    value
    |> String.to_charlist()
    |> Enum.drop_while(&blank_codepoint?/1)
    |> Enum.reverse()
    |> Enum.drop_while(&blank_codepoint?/1)
    |> Enum.reverse()
    |> List.to_string()
  end

  defp allow_keys(params) do
    if Enum.all?(Map.keys(params), &(&1 in @allowed_keys)),
      do: :ok,
      else: {:error, :invalid_input}
  end

  defp blank_codepoint?(codepoint), do: MapSet.member?(@blank_codepoint_set, codepoint)
end
