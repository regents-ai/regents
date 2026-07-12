defmodule AshPlatform.WalletActions.Address do
  @moduledoc false

  @zero "0000000000000000000000000000000000000000"

  def normalize("0x" <> address = value) when byte_size(address) == 40 do
    if address != @zero and String.match?(address, ~r/^[0-9a-fA-F]+$/),
      do: {:ok, String.downcase(value)},
      else: :error
  end

  def normalize(_value), do: :error
end
