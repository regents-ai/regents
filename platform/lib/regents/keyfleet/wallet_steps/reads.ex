defmodule Regents.Keyfleet.WalletSteps.Reads do
  @moduledoc """
  What the wallet steps read from the chain, all at one block: the head the
  site's node answers when a group of steps is built, the latest block, never
  `safe` or `finalized`. Each reader answers `{:ok, value}`, or
  `{:error, reason}` when the node or the contract didn't answer; a group whose
  reads fail builds no steps and says the chain can't be read right now.
  """

  alias RegentChain.{Abi, Call}
  alias Regents.Keyfleet.Chain.RpcClient
  alias Regents.Keyfleet.Fleets.Fleet

  @enforce_keys [:head]
  defstruct [:head]

  @type t :: %__MODULE__{head: RpcClient.head()}

  @doc "The site's node at its head block."
  def at_head do
    case RpcClient.head() do
      {:ok, head} -> {:ok, %__MODULE__{head: head}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "The head block's time, as a `DateTime`."
  def now(%__MODULE__{head: head}), do: head.timestamp

  @doc "The head block's number."
  def block(%__MODULE__{head: head}), do: head.number

  @doc "One view function's single answer, of `type`."
  def one(reads, to, signature, arguments, type) do
    with {:ok, [value]} <- many(reads, to, signature, arguments, [type]), do: {:ok, value}
  end

  @doc "One view function's answers, of `types` in order."
  def many(%__MODULE__{head: head}, to, signature, arguments, types) do
    with {:ok, returned} <- RpcClient.call(to, Call.encode(signature, arguments), head.hash),
         do: decode(returned, types)
  end

  @doc """
  Whether calling `signature` on `to` with `arguments` would go through at the
  head block, sent from no one in particular: `{:ok, false}` when the contract
  refuses it.
  """
  def goes_through?(%__MODULE__{head: head}, to, signature, arguments) do
    case RpcClient.call(to, Call.encode(signature, arguments), head.hash) do
      {:ok, _returned} -> {:ok, true}
      {:error, :reverted} -> {:ok, false}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  The logs `addresses` made with any of `topics` as their topic0, from block
  `from` to the head block: none when `from` is past the head.
  """
  def logs(%__MODULE__{head: %{number: head}}, _addresses, _topics, from) when from > head,
    do: {:ok, []}

  def logs(%__MODULE__{head: head}, addresses, topics, from),
    do: RpcClient.get_logs(addresses, topics, from, head.number)

  @doc "An account's ETH at the head block, in wei."
  def balance(%__MODULE__{head: head}, account),
    do: RpcClient.get_balance(account, head.hash)

  @doc """
  Whether `wallet` pays its own network fee and holds less ETH than any
  transaction costs at the head block, 21,000 gas at the block's base fee, so
  that whatever it sends is certain to fail. A wallet with code, a smart
  wallet or one delegating to one, may have its fee paid for it and is never
  short.
  """
  def short_of_gas?(%__MODULE__{head: head} = reads, wallet) do
    case pays_own_fee?(reads, wallet) do
      {:ok, true} ->
        with {:ok, wei} <- balance(reads, wallet), do: {:ok, wei < 21_000 * head.base_fee}

      {:ok, false} ->
        {:ok, false}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Whether `wallet` has no code at the head block, so it pays its own network fee."
  def pays_own_fee?(%__MODULE__{head: head}, wallet) do
    with {:ok, code} <- RpcClient.get_code(wallet, head.hash), do: {:ok, code == ""}
  end

  @doc """
  `read` applied to each entry in turn, stopping at the first that fails:
  `{:ok, values}` in order, or that failure.
  """
  def each(entries, read) do
    entries
    |> Enum.reduce_while({:ok, []}, fn entry, {:ok, values} ->
      case read.(entry) do
        {:ok, value} -> {:cont, {:ok, [value | values]}}
        failure -> {:halt, failure}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      failure -> failure
    end
  end

  @doc """
  Whether `wallet` may act for each key as its holder or as an active shard:
  `%{token_id => {holder, allowed?}}`. `shard_check` is `"isActive"` for a
  shard that may mark the key present or claim, and `"mayGovern"` for one that
  may also vote with it and propose with it, which needs the key's agent
  voting on.
  """
  def acting(reads, fleet, wallet, keys, shard_check) do
    with {:ok, standing} <- each(keys, &standing(reads, fleet, wallet, &1, shard_check)),
         do: {:ok, Map.new(standing)}
  end

  defp standing(reads, fleet, wallet, key, shard_check) do
    with {:ok, holder} <- holder(reads, fleet, key),
         {:ok, allowed?} <- allowed(reads, fleet, wallet, key, holder, shard_check),
         do: {:ok, {key, {holder, allowed?}}}
  end

  @doc """
  Who holds the fleet's Key number `key`, or nil for a Key not sold yet, which
  the Key collection refuses to name.
  """
  def holder(reads, fleet, key) do
    case one(
           reads,
           fleet.keys_address,
           "ownerOf(uint256)",
           [Fleet.onchain_token_id(fleet, key)],
           :address
         ) do
      {:error, :reverted} -> {:ok, nil}
      answer -> answer
    end
  end

  defp allowed(_reads, _fleet, _wallet, _key, nil, _shard_check), do: {:ok, false}
  # A visitor, with no wallet, acts for no key.
  defp allowed(_reads, _fleet, nil, _key, _holder, _shard_check), do: {:ok, false}
  defp allowed(_reads, _fleet, wallet, _key, wallet, _shard_check), do: {:ok, true}

  defp allowed(reads, fleet, wallet, key, _holder, shard_check) do
    token_id = Fleet.onchain_token_id(fleet, key)
    one(reads, fleet.shards_address, "#{shard_check}(uint256,address)", [token_id, wallet], :bool)
  end

  defp decode(returned, types) do
    case Abi.decode(returned, types) do
      {:ok, values} -> {:ok, values}
      :error -> {:error, :unreadable_answer}
    end
  end
end
