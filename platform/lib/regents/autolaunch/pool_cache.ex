defmodule Regents.Autolaunch.PoolCache do
  @moduledoc """
  What the token pages last read of a graduated token's pool, kept on this
  machine and shared by every opening of the page: the pool read from the
  chain (`Regents.Autolaunch.TokenPage.pool/2`), kept 15 seconds under its
  auction's id, and whether DexScreener has a chart for the pool
  (`Regents.Autolaunch.DexScreener`), kept a minute under the pool id. So
  however many open a token's page, its pool is read from the chain at most
  once in 15 seconds, and DexScreener asked about it at most once a minute.

  One read of a key runs at a time, under the cache's own lock on that key
  (`transaction/2`): an opening asking meanwhile waits for it, then takes what
  it kept, and openings of other tokens do not wait. A pool read that failed
  is not kept, so the next opening, and Retry, read again; DexScreener's
  answer is kept whatever it was, a failed request's no included.

  Every three seconds the cache counts what it keeps, and at 256 or more it
  drops the older of its two generations whole (set in
  `Regents.Autolaunch.Supervisor`). What is kept lives on one machine.
  """
  use Nebulex.Cache, otp_app: :regents, adapter: Nebulex.Adapters.Local

  @pool_kept :timer.seconds(15)
  @chart_kept :timer.minutes(1)

  @doc """
  The pool kept for `auction_id`, or `read`'s answer, kept 15 seconds when it
  is `{:ok, pool}`.
  """
  @spec pool(String.t(), (-> {:ok, map()} | {:error, term()})) ::
          {:ok, map()} | {:error, term()}
  def pool(auction_id, read), do: kept({:pool, auction_id}, read, @pool_kept, &read?/1)

  @doc "DexScreener's answer kept for `pool_id`, or `read`'s, kept a minute."
  @spec chart(String.t(), (-> boolean())) :: boolean()
  def chart(pool_id, read),
    do: kept({:chart, pool_id}, read, @chart_kept, fn _listed? -> true end)

  defp kept(key, read, ttl, keep?) do
    case get!(key) do
      nil -> read_once(key, read, ttl, keep?)
      answer -> answer
    end
  end

  # Under the lock on `key`, which an opening asking meanwhile waits on for as
  # long as the read takes, the read runs only if nothing is kept yet.
  defp read_once(key, read, ttl, keep?) do
    {:ok, answer} =
      transaction(
        fn ->
          case get!(key) do
            nil -> read_and_keep(key, read, ttl, keep?)
            answer -> answer
          end
        end,
        keys: [key],
        retries: :infinity
      )

    answer
  end

  defp read_and_keep(key, read, ttl, keep?) do
    answer = read.()
    if keep?.(answer), do: put!(key, answer, ttl: ttl)
    answer
  end

  defp read?({:ok, _pool}), do: true
  defp read?({:error, _reason}), do: false
end
