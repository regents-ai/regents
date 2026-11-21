defmodule Regents.Keyfleet.Chain.RewardsWaiting do
  @moduledoc """
  What one key's holder can claim from the fleet's reward ledger, in each
  asset it pays (`rewardAssets()`): what the key has accrued and not yet had
  settled (`accrued(asset, tokenId)`), and the holder's credit, which a
  claim pays out with it (`credits(asset, holder)`). Read at the block the
  node last called its head.

  An answer is kept for 30 seconds in a table this process owns, so a key
  opened again and again in that time is read from the chain once. A read
  that fails keeps nothing, and the next one asks again.
  """
  use GenServer

  alias RegentChain.Abi
  alias RegentChain.Call
  alias Regents.Keyfleet.Chain.RpcClient

  @table __MODULE__
  @kept_ms 30_000
  @reward_assets Call.encode("rewardAssets()", [])

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(nil) do
    :ets.new(@table, [:named_table, :public, read_concurrency: true])
    {:ok, nil}
  end

  @doc """
  What waits for key `token_id` of `fleet`, which names its `fleet_id`,
  `chain_fleet_id` and `rewards_address`, held by `holder`: `{:ok, [%{asset: asset, accrued:
  amount, credit: amount}]}` in the ledger's order, amounts in the asset's
  atomic units, or the chain's `{:error, reason}`. An answer read less than
  30 seconds before `now`, in monotonic milliseconds, is given again without
  asking the chain.
  """
  def read(fleet, token_id, holder, now \\ System.monotonic_time(:millisecond)) do
    key = {fleet.fleet_id, token_id, holder}

    case :ets.lookup(@table, key) do
      [{^key, waiting, read_at}] when now - read_at < @kept_ms -> {:ok, waiting}
      _unread_or_old -> read_chain(fleet, token_id, holder, key, now)
    end
  end

  defp read_chain(fleet, token_id, holder, key, now) do
    at = &call(fleet.rewards_address, &1, &2, &3)

    with {:ok, head} <- RpcClient.head(),
         {:ok, [assets]} <- at.(@reward_assets, {:array, :address}, head.hash),
         onchain_token_id = Regents.Keyfleet.Fleets.Fleet.onchain_token_id(fleet, token_id),
         {:ok, waiting} <- each_asset(assets, onchain_token_id, holder, at, head.hash) do
      :ets.insert(@table, {key, waiting, now})
      {:ok, waiting}
    end
  end

  defp each_asset(assets, onchain_token_id, holder, at, block_hash) do
    Enum.reduce_while(assets, {:ok, []}, fn asset, {:ok, waiting} ->
      accrued = Call.encode("accrued(address,uint256)", [asset, onchain_token_id])
      credit = Call.encode("credits(address,address)", [asset, holder])

      with {:ok, [accrued]} <- at.(accrued, {:uint, 256}, block_hash),
           {:ok, [credit]} <- at.(credit, {:uint, 256}, block_hash) do
        {:cont, {:ok, [%{asset: asset, accrued: accrued, credit: credit} | waiting]}}
      else
        failure -> {:halt, failure}
      end
    end)
    |> then(fn
      {:ok, waiting} -> {:ok, Enum.reverse(waiting)}
      failure -> failure
    end)
  end

  defp call(to, data, type, block_hash) do
    with {:ok, returned} <- RpcClient.call(to, data, block_hash) do
      case Abi.decode(returned, [type]) do
        {:ok, values} -> {:ok, values}
        :error -> {:error, :unreadable_answer}
      end
    end
  end
end
