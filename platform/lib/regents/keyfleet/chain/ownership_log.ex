defmodule Regents.Keyfleet.Chain.OwnershipLog do
  @moduledoc """
  Reads the Key collection's `OwnershipEpoch(uint256 indexed tokenId, uint64
  epoch, address indexed from, address indexed to)` logs into the fields
  `Regents.Keyfleet.Keys.record_epoch/2` takes.
  """

  alias RegentChain.Abi
  alias RegentChain.Event

  @topic Event.topic0("OwnershipEpoch(uint256,uint64,address,address)")

  @doc "The event's topic0."
  def topic, do: @topic

  @doc """
  An `OwnershipEpoch` log's indexed topics after topic0, as 32-byte words, and
  its data, as an ownership record; `:error` for any other log or a malformed
  one.
  """
  def decode(@topic, [token_topic, from_topic, to_topic], data) do
    with {:ok, token_id} when token_id > 0 <- Abi.word(token_topic, {:uint, 63}),
         {:ok, _from} <- Abi.word(from_topic, :address),
         {:ok, owner_wallet} <- Abi.word(to_topic, :address),
         {:ok, [ownership_epoch]} <- Abi.decode(data, [{:uint, 63}]) do
      {:ok,
       {:ownership,
        %{token_id: token_id, ownership_epoch: ownership_epoch, owner_wallet: owner_wallet}}}
    else
      _malformed -> :error
    end
  end

  def decode(_topic0, _topics, _data), do: :error
end
