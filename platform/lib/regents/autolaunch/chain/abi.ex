defmodule Regents.Autolaunch.Chain.Abi do
  @moduledoc false

  alias Regents.Chain.Address

  @address_bound Integer.pow(2, 160)

  @doc """
  The one log in this receipt that is exactly this event.

  Emitter, `topic0`, indexed count and data width all have to be exact, and the
  event has to appear exactly once: absent and duplicated are both `:error`,
  while logs belonging to other events are ignored.
  """
  def one_event(logs, topic, emitter, indexed_count, data_words) when is_list(logs) do
    case Enum.filter(logs, &emitted?(&1, topic, emitter)) do
      [log] -> decode_event(log, indexed_count, data_words)
      _absent_or_duplicated -> :error
    end
  end

  def one_event(_logs, _topic, _emitter, _indexed_count, _data_words), do: :error

  @doc "The address a 32-byte word names, which requires its leading twelve bytes to be zero."
  def word_address(value) when is_integer(value) and value > 0 and value < @address_bound,
    do:
      {:ok,
       "0x" <>
         (value |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(40, "0"))}

  def word_address(_value), do: :error

  defp emitted?(%{"address" => address, "topics" => [topic | _indexed]}, expected, emitter)
       when is_binary(topic),
       do: String.downcase(topic) == expected and Address.equal?(address, emitter)

  defp emitted?(_log, _expected, _emitter), do: false

  # Every topic after `topic0` is one whole word, and so is every 64 hex digits
  # of the data.
  defp decode_event(%{"topics" => [_topic | indexed], "data" => "0x" <> data}, count, words)
       when length(indexed) == count and byte_size(data) == words * 64 do
    topics = for "0x" <> hex <- indexed, byte_size(hex) == 64, into: "", do: hex

    with true <- byte_size(topics) == count * 64,
         {:ok, indexed} <- words(topics, []),
         {:ok, data} <- words(data, []) do
      {:ok, {indexed, data}}
    else
      _malformed -> :error
    end
  end

  defp decode_event(_log, _count, _words), do: :error

  defp words(<<>>, decoded), do: {:ok, Enum.reverse(decoded)}

  defp words(<<hex::binary-size(64), rest::binary>>, decoded) do
    case Base.decode16(hex, case: :mixed) do
      {:ok, bytes} -> words(rest, [:binary.decode_unsigned(bytes) | decoded])
      :error -> :error
    end
  end
end
