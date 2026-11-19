defmodule AgentEns.ERC7930 do
  @moduledoc """
  ERC-7930 interoperable address encoding and decoding.
  """

  alias AgentEns.Error

  @version_1 0x0001
  @chain_type_evm 0x0000

  @enforce_keys [:version, :chain_type, :chain_ref, :address]
  defstruct [:version, :chain_type, :chain_ref, :address]

  @type t :: %__MODULE__{
          version: non_neg_integer(),
          chain_type: non_neg_integer(),
          chain_ref: binary(),
          address: binary()
        }

  @spec evm(non_neg_integer(), String.t()) :: {:ok, t()} | {:error, Error.t()}
  def evm(chain_id, address) when is_integer(chain_id) and chain_id >= 0 do
    with {:ok, address_bytes} <- decode_evm_address(address) do
      {:ok,
       %__MODULE__{
         version: @version_1,
         chain_type: @chain_type_evm,
         chain_ref: minimal_be_bytes(chain_id),
         address: address_bytes
       }}
    end
  end

  @spec evm_no_chain(String.t()) :: {:ok, t()} | {:error, Error.t()}
  def evm_no_chain(address) do
    with {:ok, address_bytes} <- decode_evm_address(address) do
      {:ok,
       %__MODULE__{
         version: @version_1,
         chain_type: @chain_type_evm,
         chain_ref: <<>>,
         address: address_bytes
       }}
    end
  end

  @spec decode(binary()) :: {:ok, t()} | {:error, Error.t()}
  def decode(bytes) when is_binary(bytes) do
    if byte_size(bytes) < 6 do
      {:error, Error.new({:buffer_too_short, byte_size(bytes)})}
    else
      <<version::16, chain_type::16, chain_ref_len::8, rest::binary>> = bytes

      cond do
        version != @version_1 ->
          {:error, Error.new({:unsupported_version, version})}

        byte_size(rest) < chain_ref_len + 1 ->
          {:error, Error.new({:truncated_payload, chain_ref_len + 6, byte_size(bytes)})}

        true ->
          <<chain_ref::binary-size(^chain_ref_len), address_len::8, address_and_tail::binary>> =
            rest

          if byte_size(address_and_tail) < address_len do
            {:error,
             Error.new({:truncated_payload, chain_ref_len + address_len + 6, byte_size(bytes)})}
          else
            <<address::binary-size(^address_len), _tail::binary>> = address_and_tail

            if chain_ref_len == 0 and address_len == 0 do
              {:error, Error.new(:empty_address)}
            else
              {:ok,
               %__MODULE__{
                 version: version,
                 chain_type: chain_type,
                 chain_ref: chain_ref,
                 address: address
               }}
            end
          end
      end
    end
  end

  @spec from_hex(String.t()) :: {:ok, t()} | {:error, Error.t()}
  def from_hex(value) when is_binary(value) do
    value
    |> strip_hex_prefix()
    |> Base.decode16(case: :mixed)
    |> case do
      {:ok, bytes} -> decode(bytes)
      :error -> {:error, Error.new({:hex_decode, "invalid hex"})}
    end
  end

  @spec encode(t()) :: binary()
  def encode(%__MODULE__{} = address) do
    <<
      address.version::16,
      address.chain_type::16,
      byte_size(address.chain_ref)::8,
      address.chain_ref::binary,
      byte_size(address.address)::8,
      address.address::binary
    >>
  end

  @spec to_hex(t()) :: String.t()
  def to_hex(%__MODULE__{} = address) do
    "0x" <> Base.encode16(encode(address), case: :lower)
  end

  @spec is_evm?(t()) :: boolean()
  def is_evm?(%__MODULE__{chain_type: chain_type}), do: chain_type == @chain_type_evm

  @spec evm_chain_id(t()) :: non_neg_integer() | nil
  def evm_chain_id(%__MODULE__{chain_ref: <<>>}), do: nil

  def evm_chain_id(%__MODULE__{chain_ref: chain_ref}) when byte_size(chain_ref) <= 8 do
    padded = :binary.copy(<<0>>, 8 - byte_size(chain_ref)) <> chain_ref
    <<value::unsigned-big-integer-size(64)>> = padded
    value
  end

  def evm_chain_id(%__MODULE__{}), do: nil

  @spec evm_address(t()) :: String.t() | nil
  def evm_address(%__MODULE__{address: <<raw::binary-size(20)>>}) do
    "0x" <> Base.encode16(raw, case: :lower)
  end

  def evm_address(%__MODULE__{}), do: nil

  defimpl String.Chars do
    def to_string(address), do: AgentEns.ERC7930.to_hex(address)
  end

  defimpl Inspect do
    import Inspect.Algebra

    def inspect(address, _opts) do
      concat([
        "#AgentEns.ERC7930<",
        AgentEns.ERC7930.to_hex(address),
        ">"
      ])
    end
  end

  defp decode_evm_address("0x" <> hex), do: decode_evm_address(hex)

  defp decode_evm_address(hex) when is_binary(hex) and byte_size(hex) == 40 do
    case Base.decode16(hex, case: :mixed) do
      {:ok, <<_::binary-size(20)>> = address} -> {:ok, address}
      _ -> {:error, Error.new({:invalid_address, "0x" <> hex})}
    end
  end

  defp decode_evm_address(value), do: {:error, Error.new({:invalid_address, to_string(value)})}

  defp minimal_be_bytes(0), do: <<0>>

  defp minimal_be_bytes(value) when is_integer(value) and value > 0 do
    value
    |> :binary.encode_unsigned(:big)
  end

  defp strip_hex_prefix("0x" <> rest), do: rest
  defp strip_hex_prefix(value), do: value
end
