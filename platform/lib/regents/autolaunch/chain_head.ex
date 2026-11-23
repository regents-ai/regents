defmodule Regents.Autolaunch.ChainHead do
  @moduledoc """
  The newest block of each auction deployment, read once for every open page
  and held in `Regents.SharedReading` under `key/1`: the block number for
  Base Revstake (`"base"`) and Base Memestock (`"stocks"`), and the rollup
  clock the Robinhood contracts keep time by (`"robinhood"`,
  `Regents.Autolaunch.Robinhood.BlockClock`). It is the clock a page draws time passing
  by; a key marked degraded says the site could not read that chain on its last
  attempt. One runs for each configured deployment on each machine that serves
  pages: every second on a lab, every five minutes on mainnet, and within ten
  seconds of a person's on-chain press landing on its chain (`refresh/1`, from
  `Regents.Autolaunch.ChainRefresh`).

  This is ash-template's `AshTemplate.ChainHead`, a supervised reader of an
  outside clock, one of the two shapes the `elixir-stack` skill lets reread on
  their own. Nothing here is work that could be lost: it holds no queue and no
  copy of database rows, never writes the database, and stores only through
  `SharedReading`; a read that fails is not tried again, because the next one
  replaces it.

  The first read happens as the reader starts, so the key holds a reading or
  its degraded mark before the site serves a page. Each later read is scheduled
  only when the last has finished, so reads never pile up behind a slow node.
  """

  use GenServer

  @behaviour Regents.Chain.Refresh

  alias Regents.Autolaunch.Chain.Rpc
  alias Regents.Autolaunch.Lab
  alias Regents.Autolaunch.Robinhood.BlockClock
  alias Regents.Autolaunch.Robinhood.Lab, as: RobinhoodLab
  alias Regents.Autolaunch.Stocks.Lab, as: StocksLab
  alias Regents.Chain.Refresh, as: ChainRefresh
  alias Regents.ProductActivity
  alias Regents.SharedReading

  @lab_every_ms 1_000
  @mainnet_every_ms 300_000

  @doc "One reader for each auction deployment this site describes."
  def children do
    for {feed, every_ms} <- configured() do
      Supervisor.child_spec({__MODULE__, {feed, every_ms}}, id: {__MODULE__, feed})
    end
  end

  defp configured do
    for {feed, true, lab?} <- [
          {"base", match?({:ok, _config}, Lab.current()), Lab.test_chain?()},
          {"stocks", match?({:ok, _config}, StocksLab.current()), Lab.test_chain?()},
          {"robinhood", RobinhoodLab.configured?(), RobinhoodLab.test_chain?()}
        ],
        do: {feed, if(lab?, do: @lab_every_ms, else: @mainnet_every_ms)}
  end

  @doc "Where the newest block of deployment `feed` is held."
  def key(feed) when feed in ["base", "stocks", "robinhood"], do: {:chain_head, feed}

  @doc """
  The newest block of `feed` and whether its last read failed, or nil while it
  has never been read.
  """
  @spec fetch(String.t()) :: %{block: non_neg_integer() | nil, degraded?: boolean()} | nil
  def fetch(feed) do
    case SharedReading.fetch(key(feed)) do
      {:ok, %{reading: block, degraded?: degraded?}} -> %{block: block, degraded?: degraded?}
      :error -> nil
    end
  end

  @doc """
  The newest block of `feed` as the site last read it, the clock a page draws
  time passing by, or nil while it has never been read.
  """
  @spec block(String.t()) :: non_neg_integer() | nil
  def block(feed), do: fetch(feed)[:block]

  @doc "Whether the site could not read `feed`'s chain on its last attempt."
  @spec stale?(String.t()) :: boolean()
  def stale?(feed), do: match?(%{degraded?: true}, fetch(feed))

  @doc "Reads every deployment on chain `chain_id` again soon, on every machine."
  @impl ChainRefresh
  def refresh(chain_id) do
    for {feed, _every_ms} <- configured(),
        chain_id(feed) == chain_id,
        do: Phoenix.PubSub.broadcast(Regents.PubSub, topic(feed), :chain_refresh)

    :ok
  end

  defp chain_id("base"), do: Lab.chain_id()
  defp chain_id("stocks"), do: Lab.chain_id()
  defp chain_id("robinhood"), do: RobinhoodLab.chain_id()

  defp topic(feed), do: "chain_head:#{feed}"

  def start_link({feed, every_ms}) when is_binary(feed) and every_ms >= 1_000,
    do: GenServer.start_link(__MODULE__, {feed, every_ms})

  @impl true
  def init({feed, every_ms}) do
    SharedReading.register_producer(key(feed), self(), :async)
    :ok = ProductActivity.subscribe()
    :ok = Phoenix.PubSub.subscribe(Regents.PubSub, topic(feed))
    {:ok, %{feed: feed, every_ms: every_ms, read_at: nil, timer: nil, active?: false}}
  end

  @impl true
  def handle_cast(:wake, %{active?: true} = head), do: {:noreply, head}

  def handle_cast(:wake, %{feed: feed} = head) do
    ProductActivity.touch(:autolaunch)
    SharedReading.mark_loaded(key(feed), true)
    {:noreply, read(%{head | active?: true})}
  end

  @impl true
  def handle_info({:product_idle, :autolaunch}, %{active?: true} = head),
    do: {:noreply, sleep(head)}

  def handle_info({:product_idle, _product}, head), do: {:noreply, head}
  def handle_info({:product_active, _product}, head), do: {:noreply, head}

  def handle_info(:read, %{active?: true} = head) do
    if ProductActivity.active?(:autolaunch),
      do: {:noreply, read(head)},
      else: {:noreply, sleep(head)}
  end

  def handle_info(:read, head), do: {:noreply, head}

  # A press landed: read again once ten seconds have passed since the last
  # read began, unless the next read is due sooner.
  def handle_info(:chain_refresh, %{read_at: nil, feed: feed} = head) do
    SharedReading.mark_loaded(key(feed), true)
    {:noreply, read(%{head | active?: true})}
  end

  def handle_info(:chain_refresh, head) do
    wait = max(head.read_at + ChainRefresh.gap_s() * 1_000 - now(), 0)

    case head.timer && Process.read_timer(head.timer) do
      left when is_integer(left) and left > wait ->
        Process.cancel_timer(head.timer)
        {:noreply, %{head | active?: true, timer: Process.send_after(self(), :read, wait)}}

      left when is_integer(left) ->
        {:noreply, head}

      _none ->
        {:noreply, %{head | active?: true, timer: Process.send_after(self(), :read, wait)}}
    end
  end

  defp sleep(%{feed: feed, timer: timer} = head) do
    if timer, do: Process.cancel_timer(timer)
    SharedReading.mark_loaded(key(feed), false)
    SharedReading.delete(key(feed))
    %{head | active?: false, read_at: nil, timer: nil}
  end

  defp read(%{feed: feed} = head) do
    read_at = now()

    case newest(feed) do
      {:ok, block} -> SharedReading.put(key(feed), block)
      {:error, _reason} -> SharedReading.degraded(key(feed))
    end

    %{head | read_at: read_at, timer: Process.send_after(self(), :read, head.every_ms)}
  end

  defp newest("base") do
    with {:ok, config} <- Lab.current(),
         {:ok, block} <- Rpc.latest_block(Lab.rpc_opts(config, "chain head")),
         do: {:ok, block.number}
  end

  defp newest("stocks") do
    with {:ok, config} <- StocksLab.current(),
         {:ok, block} <- Rpc.latest_block(StocksLab.rpc_opts(config, "chain head")),
         do: {:ok, block.number}
  end

  defp newest("robinhood") do
    with {:ok, config} <- RobinhoodLab.current(),
         opts = RobinhoodLab.rpc_opts(config),
         {:ok, block} <- Rpc.latest_block(opts),
         do: BlockClock.read(block, opts)
  end

  defp now, do: System.monotonic_time(:millisecond)
end
