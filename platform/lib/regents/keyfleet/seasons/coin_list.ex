defmodule Regents.Keyfleet.Seasons.CoinList do
  @moduledoc """
  The products a pick may name now (`Regents.Keyfleet.Seasons.Coinbase.eligible/0`),
  read once for every pick and held in `Regents.SharedReading` under `key/0`.
  One runs on each machine that serves pages.

  This is a reread on notice, one of the two shapes the `elixir-stack` skill
  lets keep a shared reading: every ten minutes `Regents.SharedReading.Heal`
  asks for the list to be read again, so Coinbase is asked at most once in ten
  minutes on each machine, however many picks arrive. It holds nothing, and it
  never writes the database.

  The first read follows its start, so the site's start never waits on
  Coinbase. Until it has a reading, or while its last read failed, a pick is
  refused as not checked; the season's start checks every pick again anyway.
  """

  use GenServer

  alias Regents.Keyfleet.Seasons.Coinbase
  alias Regents.ProductActivity
  alias Regents.SharedReading

  @kind :keyfleet_season_coins

  @doc "Where the list is held."
  def key, do: {@kind, "coinbase"}

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil)

  @impl true
  def init(nil) do
    SharedReading.register_producer(@kind, self(), :sync)
    SharedReading.subscribe_heal(@kind)
    ProductActivity.subscribe()
    {:ok, %{loaded?: false}}
  end

  @impl true
  def handle_call(:ensure_loaded, _from, %{loaded?: true} = state), do: {:reply, :ok, state}

  def handle_call(:ensure_loaded, _from, state) do
    ProductActivity.touch(:keyfleet)
    read()
    SharedReading.mark_loaded(@kind, true)
    {:reply, :ok, %{state | loaded?: true}}
  end

  @impl true
  def handle_info({:product_idle, :keyfleet}, %{loaded?: true} = state) do
    SharedReading.mark_loaded(@kind, false)
    SharedReading.clear_kind(@kind)
    {:noreply, %{state | loaded?: false}}
  end

  def handle_info({:product_idle, _product}, state), do: {:noreply, state}
  def handle_info({:product_active, _product}, state), do: {:noreply, state}

  def handle_info({:shared_reading_heal, @kind}, %{loaded?: true} = state) do
    if ProductActivity.active?(:keyfleet), do: read()
    {:noreply, state}
  end

  def handle_info({:shared_reading_heal, @kind}, state), do: {:noreply, state}

  @doc "Reads the list now and holds it, or marks it not read."
  def read do
    with {:ok, product_ids} <- Coinbase.eligible(),
         :ok <- SharedReading.put(key(), product_ids) do
      :ok
    else
      {:error, _not_held} -> SharedReading.degraded(key())
    end
  end

  @doc """
  The products a pick may name now, by the list read last, and when it was
  read: `{:error, :unavailable}` while there is none, or its last read failed,
  and every pick is refused as not checked.
  """
  @spec listing() :: {:ok, [String.t()], DateTime.t()} | {:error, :unavailable}
  def listing do
    case SharedReading.fetch(key()) do
      {:ok, %{reading: [_ | _] = product_ids, at: at, degraded?: false}} -> {:ok, product_ids, at}
      _not_read -> {:error, :unavailable}
    end
  end

  @doc "Whether `product` may be picked, by the list read last."
  @spec check(String.t()) :: :ok | {:error, :ineligible | :unavailable}
  def check(product) do
    with {:ok, product_ids, _at} <- listing() do
      if product in product_ids, do: :ok, else: {:error, :ineligible}
    end
  end
end
