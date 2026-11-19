defmodule AgentEns.Address do
  @moduledoc """
  EVM address helpers shared across Regent apps: normalization, validation,
  and EIP-55 checksum encoding.
  """

  @address_regex ~r/^0[xX][a-fA-F0-9]{40}$/

  @doc """
  Normalizes an address to trimmed, lowercase `0x`-hex form.

  Returns `nil` for anything that is not a well-formed 20-byte hex address.
  """
  @spec normalize(term()) :: String.t() | nil
  def normalize(value) when is_binary(value) do
    trimmed = String.trim(value)

    if Regex.match?(@address_regex, trimmed) do
      String.downcase(trimmed)
    else
      nil
    end
  end

  def normalize(_value), do: nil

  @doc "Returns `true` when `value` is a well-formed 20-byte hex address."
  @spec valid?(term()) :: boolean()
  def valid?(value), do: not is_nil(normalize(value))

  @doc """
  Encodes an address in EIP-55 checksum form for display.
  """
  @spec checksum(term()) :: {:ok, String.t()} | {:error, :invalid_address}
  def checksum(value) do
    case normalize(value) do
      nil -> {:error, :invalid_address}
      "0x" <> address -> {:ok, "0x" <> checksum_chars(address)}
    end
  end

  defp checksum_chars(address) do
    hash =
      address
      |> ExKeccak.hash_256()
      |> Base.encode16(case: :lower)

    address
    |> String.graphemes()
    |> Enum.with_index()
    |> Enum.map_join(fn {character, index} ->
      if checksum_uppercase?(character, hash, index) do
        String.upcase(character)
      else
        character
      end
    end)
  end

  defp checksum_uppercase?(character, hash, index) do
    character =~ ~r/[a-f]/ and
      hash
      |> String.at(index)
      |> String.to_integer(16)
      |> Kernel.>=(8)
  end
end
