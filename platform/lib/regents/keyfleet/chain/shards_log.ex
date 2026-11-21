defmodule Regents.Keyfleet.Chain.ShardsLog do
  @moduledoc """
  Reads a fleet's `KeyfleetShards` logs into the fields `Regents.Keyfleet.Keys`
  records: `ShardIssued(uint256 indexed tokenId, address indexed wallet,
  uint64 expiresAt, uint64 epoch)` and `ShardEnded(uint256 indexed tokenId,
  address indexed wallet, address indexed by)`, both as `{:shard, fields}`,
  and `AgentVotingSet(uint256 indexed tokenId, bool on, uint64 epoch)`, as
  `{:agent_voting, fields}`: whether the key's shards may vote and propose
  while the key stays with the owner of that ownership epoch.
  """

  alias RegentChain.Abi
  alias RegentChain.Event

  @issued Event.topic0("ShardIssued(uint256,address,uint64,uint64)")
  @ended Event.topic0("ShardEnded(uint256,address,address)")
  @agent_voting Event.topic0("AgentVotingSet(uint256,bool,uint64)")

  @doc "The topic0 of every event read here."
  def topics, do: [@issued, @ended, @agent_voting]

  @doc "The topic0 of `ShardIssued`."
  def issued_topic, do: @issued

  @doc """
  A log's indexed topics after topic0, as 32-byte words, and its data, as one
  record; `:error` for any other log or a malformed one.
  """
  def decode(@issued, [token_topic, wallet_topic], data) do
    with {:ok, token_id} when token_id > 0 <- Abi.word(token_topic, {:uint, 63}),
         {:ok, wallet} <- Abi.word(wallet_topic, :address),
         {:ok, [expires_at, epoch]} <- Abi.decode(data, [{:uint, 63}, {:uint, 63}]),
         true <- epoch > 0,
         {:ok, expires_at} <- DateTime.from_unix(expires_at) do
      {:ok,
       {:shard,
        %{
          kind: :issued,
          token_id: token_id,
          wallet: wallet,
          expires_at: expires_at,
          ownership_epoch: epoch,
          ended_by: nil
        }}}
    else
      _malformed -> :error
    end
  end

  def decode(@ended, [token_topic, wallet_topic, by_topic], data) do
    with {:ok, token_id} when token_id > 0 <- Abi.word(token_topic, {:uint, 63}),
         {:ok, wallet} <- Abi.word(wallet_topic, :address),
         {:ok, ended_by} <- Abi.word(by_topic, :address),
         {:ok, []} <- Abi.decode(data, []) do
      {:ok,
       {:shard,
        %{
          kind: :ended,
          token_id: token_id,
          wallet: wallet,
          expires_at: nil,
          ownership_epoch: nil,
          ended_by: ended_by
        }}}
    else
      _malformed -> :error
    end
  end

  def decode(@agent_voting, [token_topic], data) do
    with {:ok, token_id} when token_id > 0 <- Abi.word(token_topic, {:uint, 63}),
         {:ok, [on, epoch]} when epoch > 0 <- Abi.decode(data, [:bool, {:uint, 63}]) do
      {:ok, {:agent_voting, %{token_id: token_id, allowed: on, ownership_epoch: epoch}}}
    else
      _malformed -> :error
    end
  end

  def decode(_topic0, _topics, _data), do: :error
end
