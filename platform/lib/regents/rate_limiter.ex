defmodule Regents.RateLimiter do
  @moduledoc """
  Fixed-window request budgets in one ETS table, kept in memory on each instance
  (the template's `AshTemplate.Accounts.RequestRateLimiter`).

  This is a per-instance best-effort bound, not a global hard cap. With N
  application instances, a caller can make up to N × limit requests in one
  window. Replace this with a distributed budget before scaling out.

  Every answer carries what is left of the window, so a response can tell the
  caller how many requests remain and when the window resets.
  """

  use GenServer

  @table __MODULE__

  @type budget :: %{
          limit: pos_integer(),
          remaining: non_neg_integer(),
          reset: pos_integer(),
          window: pos_integer()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @doc "The machine's clock in whole seconds, which `:rate_limiter_clock` names outside tests."
  @spec monotonic_second() :: integer()
  def monotonic_second, do: System.monotonic_time(:second)

  @spec admit(term(), pos_integer(), pos_integer()) ::
          {:ok, budget()} | {:error, :rate_limited, budget()}
  def admit(key, limit, window_seconds) do
    now = Application.fetch_env!(:regents, :rate_limiter_clock).()
    bucket = Integer.floor_div(now, window_seconds)
    sweep(window_seconds, bucket)
    # Each window has its own row, so a new window starts from a fresh counter.
    row = {window_seconds, key, bucket}
    count = :ets.update_counter(@table, row, {2, 1}, {row, 0})

    budget = %{
      limit: limit,
      remaining: max(limit - count, 0),
      reset: (bucket + 1) * window_seconds - now,
      window: window_seconds
    }

    if count <= limit, do: {:ok, budget}, else: {:error, :rate_limited, budget}
  end

  @doc false
  @spec reset() :: :ok
  def reset do
    :ets.delete_all_objects(@table)
    :ok
  end

  # The first request of a window drops that window's older counters, and the
  # older sweep markers with them.
  defp sweep(window_seconds, bucket) do
    if :ets.insert_new(@table, {{:swept, window_seconds, bucket}}) do
      :ets.select_delete(@table, [
        {{{window_seconds, :_, :"$1"}, :_}, [{:<, :"$1", bucket}], [true]},
        {{{:swept, window_seconds, :"$1"}}, [{:<, :"$1", bucket}], [true]}
      ])
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
end
