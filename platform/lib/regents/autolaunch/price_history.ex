defmodule Regents.Autolaunch.PriceHistory do
  @moduledoc """
  A graduated token's price since its pool opened, read from the chain's own
  logs each time a page asks.

  The PoolManager's `Initialize` log for the pool gives the opening price and
  each `Swap` log the price the trade left behind. `points` has one
  `[block, price]` pair per log, the last price carried to the block the page
  read at, thinned to 400 evenly spaced points that always keep the first and
  the last; `trades` is the number of `Swap` logs. A token's page shows how far
  the price has moved from the first point to the last, and the number of
  trades.

  The prices are floats: they say how far the price moved to a tenth of a
  percent, while every exact price a page states keeps coming from its exact
  reads.
  """

  alias Regents.Autolaunch.LabAbi
  alias Regents.Chain.Rpc

  @max_points 400
  @q96 Integer.pow(2, 96)
  @sqrt_price_bound Integer.pow(2, 160)
  @token_decimals 18
  @initialize "Initialize(bytes32,address,address,uint24,int24,address,uint160,int24)"
  @swap "Swap(bytes32,address,int128,int128,uint160,uint128,int24,uint24)"

  @type point :: [number()]
  @type history :: %{points: [point()], trades: non_neg_integer()}

  @doc """
  A pool's price after every trade from `from_block` to the pinned block, and
  the number of trades. `pool` names the PoolManager, the pool id, which side
  the token is on and the currency's decimals. A pool with no logs yet has no
  history.
  """
  @spec pool(map(), non_neg_integer(), Rpc.block(), keyword()) ::
          {:ok, history() | nil} | {:error, atom()}
  def pool(pool, from_block, block, opts) do
    topics = [[LabAbi.topic(@initialize), LabAbi.topic(@swap)], pool.pool_id]

    with {:ok, logs} <- Rpc.logs(pool.pool_manager, topics, from_block, block.number, opts),
         {:ok, moments} <- moments(logs, block, pool) do
      {:ok, history(moments, block)}
    end
  end

  defp history([], _block), do: nil

  defp history(moments, block) do
    {_number, _event, last} = List.last(moments)
    points = Enum.map(moments, fn {number, _event, price} -> [number, price] end)

    %{
      points: thin(points ++ [[block.number, last]]),
      trades: Enum.count(moments, &match?({_number, :swap, _price}, &1))
    }
  end

  # Each log's block, event and price, in chain order. A removed log, one past
  # the pinned block, or one that is not this pool's `Initialize` or `Swap`
  # means the history moved under the read or the answer is not the chain's.
  defp moments(logs, block, pool) do
    logs
    |> Enum.reduce_while({:ok, []}, fn log, {:ok, found} ->
      with %{
             "removed" => false,
             "blockNumber" => "0x" <> number,
             "topics" => [topic | _indexed],
             "data" => "0x" <> data
           } <- log,
           {number, ""} when number <= block.number <- Integer.parse(number, 16),
           {:ok, event} <- event(topic),
           {:ok, words} <- words(data),
           {:ok, sqrt_price} <- sqrt_price(event, words) do
        price = pool_price(sqrt_price, pool.token_is_currency0?, pool.currency_decimals)
        {:cont, {:ok, [{number, event, price} | found]}}
      else
        _invalid -> {:halt, {:error, :invalid_chain_response}}
      end
    end)
    |> case do
      {:ok, found} -> {:ok, Enum.reverse(found)}
      error -> error
    end
  end

  defp event(topic) when is_binary(topic) do
    initialize = LabAbi.topic(@initialize)
    swap = LabAbi.topic(@swap)

    case String.downcase(topic) do
      ^initialize -> {:ok, :initialize}
      ^swap -> {:ok, :swap}
      _other -> :error
    end
  end

  defp event(_topic), do: :error

  # `Initialize` carries the opening price in its fourth data word, `Swap` the
  # price after the trade in its third.
  defp sqrt_price(:initialize, [_fee, _spacing, _hooks, sqrt_price | _rest]),
    do: in_range(sqrt_price)

  defp sqrt_price(:swap, [_amount0, _amount1, sqrt_price | _rest]), do: in_range(sqrt_price)
  defp sqrt_price(_event, _words), do: :error

  defp in_range(sqrt_price) when sqrt_price > 0 and sqrt_price < @sqrt_price_bound,
    do: {:ok, sqrt_price}

  defp in_range(_sqrt_price), do: :error

  # `sqrtPriceX96` squared is currency1 base units per currency0 base unit.
  defp pool_price(sqrt_price, token_is_currency0?, currency_decimals) do
    ratio = :math.pow(sqrt_price / @q96, 2)
    per_base_unit = if token_is_currency0?, do: ratio, else: 1 / ratio
    per_base_unit * :math.pow(10, @token_decimals - currency_decimals)
  end

  defp thin(points) when length(points) <= @max_points, do: points

  defp thin(points) do
    count = length(points)
    indexed = List.to_tuple(points)

    for step <- 0..(@max_points - 1),
        do: elem(indexed, div(step * (count - 1), @max_points - 1))
  end

  defp words(hex) when rem(byte_size(hex), 64) == 0 do
    case Base.decode16(hex, case: :mixed) do
      {:ok, bytes} -> {:ok, for(<<word::256 <- bytes>>, do: word)}
      :error -> :error
    end
  end

  defp words(_hex), do: :error
end
