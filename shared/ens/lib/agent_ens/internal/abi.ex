defmodule AgentEns.Internal.ABI do
  @moduledoc false

  alias AgentEns.Error

  @spec selector(String.t()) :: String.t()
  def selector(signature) when is_binary(signature) do
    "0x" <>
      (signature
       |> ExKeccak.hash_256()
       |> binary_part(0, 4)
       |> Base.encode16(case: :lower))
  end

  @spec encode_call(String.t(), list()) :: {:ok, String.t()} | {:error, Error.t()}
  def encode_call(signature, args) when is_binary(signature) and is_list(args) do
    with {:ok, encoded_args} <- encode_args(args) do
      {:ok, selector(signature) <> encoded_args}
    end
  end

  @spec decode_address(String.t()) :: {:ok, String.t()} | {:error, Error.t()}
  def decode_address("0x" <> payload) when byte_size(payload) == 64 do
    {:ok, "0x" <> String.slice(String.downcase(payload), -40, 40)}
  end

  def decode_address(result), do: {:error, Error.new({:invalid_rpc_result, result})}

  @spec decode_bool(String.t()) :: {:ok, boolean()} | {:error, Error.t()}
  def decode_bool("0x" <> payload) when byte_size(payload) == 64 do
    case String.to_integer(payload, 16) do
      0 -> {:ok, false}
      1 -> {:ok, true}
      other -> {:error, Error.new({:invalid_rpc_result, other})}
    end
  rescue
    _ -> {:error, Error.new({:invalid_rpc_result, payload})}
  end

  def decode_bool(result), do: {:error, Error.new({:invalid_rpc_result, result})}

  @spec decode_uint256(String.t()) :: {:ok, non_neg_integer()} | {:error, Error.t()}
  def decode_uint256("0x" <> payload) when byte_size(payload) == 64 do
    {:ok, String.to_integer(payload, 16)}
  rescue
    _ -> {:error, Error.new({:invalid_rpc_result, payload})}
  end

  def decode_uint256(result), do: {:error, Error.new({:invalid_rpc_result, result})}

  @spec decode_string(String.t()) :: {:ok, String.t()} | {:error, Error.t()}
  def decode_string("0x" <> payload) when rem(byte_size(payload), 64) == 0 do
    with {:ok, data} <- decode_dynamic_binary(payload) do
      {:ok, data}
    else
      {:error, %Error{} = error} -> {:error, error}
      _ -> {:error, Error.new({:invalid_rpc_result, payload})}
    end
  end

  def decode_string(result), do: {:error, Error.new({:invalid_rpc_result, result})}

  @spec decode_bytes(String.t()) :: {:ok, binary()} | {:error, Error.t()}
  def decode_bytes("0x" <> payload) when rem(byte_size(payload), 64) == 0 do
    decode_dynamic_binary(payload)
  end

  def decode_bytes(result), do: {:error, Error.new({:invalid_rpc_result, result})}

  @spec uint256_word(non_neg_integer()) :: String.t()
  def uint256_word(value) when is_integer(value) and value >= 0 do
    value |> Integer.to_string(16) |> String.pad_leading(64, "0")
  end

  @spec bytes32_word(binary()) :: {:ok, String.t()} | {:error, Error.t()}
  def bytes32_word(value) when is_binary(value) and byte_size(value) == 32 do
    {:ok, Base.encode16(value, case: :lower)}
  end

  def bytes32_word(value), do: {:error, Error.new({:abi_error, {:expected_bytes32, value}})}

  @spec address_word(String.t()) :: {:ok, String.t()} | {:error, Error.t()}
  def address_word("0x" <> rest) when byte_size(rest) == 40 do
    {:ok, String.pad_leading(String.downcase(rest), 64, "0")}
  end

  def address_word(value), do: {:error, Error.new({:invalid_address, inspect(value)})}

  @spec bytes4_word(String.t()) :: {:ok, String.t()} | {:error, Error.t()}
  def bytes4_word("0x" <> rest) when byte_size(rest) == 8 do
    {:ok, String.downcase(rest) <> String.duplicate("0", 56)}
  end

  def bytes4_word(value), do: {:error, Error.new({:abi_error, {:expected_bytes4, value}})}

  @spec string_tail(String.t()) :: String.t()
  def string_tail(value) when is_binary(value) do
    bytes_tail(:erlang.iolist_to_binary(value))
  end

  @spec bytes_tail(binary()) :: String.t()
  def bytes_tail(value) when is_binary(value) do
    hex = Base.encode16(value, case: :lower)

    uint256_word(byte_size(value)) <>
      hex <>
      String.duplicate("0", rem(64 - rem(byte_size(hex), 64), 64))
  end

  defp encode_args(args), do: encode_args(args, "", "", length(args))

  defp encode_args([], head, tail, _dynamic_words), do: {:ok, head <> tail}

  defp encode_args([{:uint256, value} | rest], head, tail, dynamic_words) do
    encode_args(rest, head <> uint256_word(value), tail, dynamic_words)
  end

  defp encode_args([{:bytes32, value} | rest], head, tail, dynamic_words) do
    with {:ok, word} <- bytes32_word(value) do
      encode_args(rest, head <> word, tail, dynamic_words)
    end
  end

  defp encode_args([{:address, value} | rest], head, tail, dynamic_words) do
    with {:ok, word} <- address_word(value) do
      encode_args(rest, head <> word, tail, dynamic_words)
    end
  end

  defp encode_args([{:bytes4, value} | rest], head, tail, dynamic_words) do
    with {:ok, word} <- bytes4_word(value) do
      encode_args(rest, head <> word, tail, dynamic_words)
    end
  end

  defp encode_args([{:string, value} | rest], head, tail, dynamic_words) do
    encode_dynamic_arg(string_tail(value), rest, head, tail, dynamic_words)
  end

  defp encode_args([{:bytes, value} | rest], head, tail, dynamic_words) when is_binary(value) do
    encode_dynamic_arg(bytes_tail(value), rest, head, tail, dynamic_words)
  end

  defp encode_args([invalid | _rest], _head, _tail, _dynamic_words) do
    {:error, Error.new({:abi_error, {:unsupported_arg, invalid}})}
  end

  defp encode_dynamic_arg(encoded_tail, rest, head, tail, dynamic_words) do
    offset_bytes = dynamic_words * 32
    new_words = dynamic_words + div(byte_size(encoded_tail), 64)
    encode_args(rest, head <> uint256_word(offset_bytes), tail <> encoded_tail, new_words)
  end

  defp read_word(payload, offset) do
    start = offset * 2

    if byte_size(payload) >= start + 64 do
      {:ok, String.to_integer(binary_part(payload, start, 64), 16)}
    else
      {:error, Error.new({:invalid_rpc_result, payload})}
    end
  rescue
    _ -> {:error, Error.new({:invalid_rpc_result, payload})}
  end

  defp ensure_offset(payload, offset) when offset + 32 <= div(byte_size(payload), 2), do: :ok
  defp ensure_offset(payload, _offset), do: {:error, Error.new({:invalid_rpc_result, payload})}

  defp ensure_bounds(payload, data_start, data_hex_length)
       when byte_size(payload) >= data_start * 2 + data_hex_length,
       do: :ok

  defp ensure_bounds(payload, _data_start, _data_hex_length),
    do: {:error, Error.new({:invalid_rpc_result, payload})}

  defp decode_dynamic_binary(payload) do
    with {:ok, offset} <- read_word(payload, 0),
         :ok <- ensure_offset(payload, offset),
         {:ok, length} <- read_word(payload, offset),
         data_start = offset + 32,
         data_hex_length = length * 2,
         :ok <- ensure_bounds(payload, data_start, data_hex_length),
         binary_hex <- binary_part(payload, data_start * 2, data_hex_length),
         {:ok, data} <- Base.decode16(binary_hex, case: :mixed) do
      {:ok, data}
    else
      {:error, %Error{} = error} -> {:error, error}
      _ -> {:error, Error.new({:invalid_rpc_result, payload})}
    end
  end
end
