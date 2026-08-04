defmodule AshPlatform.AgentAuth.ClaimRateLimiter do
  @moduledoc false
  use GenServer

  @table __MODULE__
  @limit 10
  @window_seconds 60

  def admit(remote_ip) do
    table = ensure_table()
    bucket = System.monotonic_time(:second) |> div(@window_seconds)
    sweep_expired(table, bucket)
    increment(table, remote_ip, bucket)
  end

  @doc false
  def reset do
    case :ets.whereis(@table) do
      :undefined -> :ok
      table -> :ets.delete_all_objects(table)
    end
  end

  defp increment(table, remote_ip, bucket) do
    case :ets.lookup(table, remote_ip) do
      [] ->
        insert_first(table, remote_ip, bucket)

      [{^remote_ip, ^bucket, _count}] ->
        increment_current(table, remote_ip)

      [{^remote_ip, old_bucket, count}] ->
        reset_expired(table, remote_ip, old_bucket, count, bucket)
    end
  end

  defp insert_first(table, remote_ip, bucket) do
    if :ets.insert_new(table, {remote_ip, bucket, 1}),
      do: :ok,
      else: increment(table, remote_ip, bucket)
  end

  defp increment_current(table, remote_ip) do
    if :ets.update_counter(table, remote_ip, {3, 1}) <= @limit,
      do: :ok,
      else: {:error, :rate_limited}
  end

  defp reset_expired(table, remote_ip, old_bucket, count, bucket) do
    replacement = [{{remote_ip, old_bucket, count}, [], [{{remote_ip, bucket, 1}}]}]

    if :ets.select_replace(table, replacement) == 1,
      do: :ok,
      else: increment(table, remote_ip, bucket)
  end

  defp sweep_expired(table, bucket) do
    if :ets.insert_new(table, {{:sweep, bucket}, true}) do
      :ets.select_delete(table, [{{:"$1", :"$2", :"$3"}, [{:<, :"$2", bucket}], [true]}])

      :ets.select_delete(table, [
        {{{:sweep, :"$1"}, :"$2"}, [{:<, :"$1", bucket}], [true]}
      ])
    end

    :ok
  end

  defp ensure_table do
    owner = Process.whereis(__MODULE__) || start_owner()
    GenServer.call(owner, :table)
  end

  defp start_owner do
    case GenServer.start(__MODULE__, nil, name: __MODULE__) do
      {:ok, owner} -> owner
      {:error, {:already_started, owner}} -> owner
    end
  end

  @impl true
  def init(nil) do
    :ets.new(@table, [
      :named_table,
      :public,
      :set,
      read_concurrency: true,
      write_concurrency: true
    ])

    {:ok, nil}
  end

  @impl true
  def handle_call(:table, _from, state), do: {:reply, @table, state}
end
