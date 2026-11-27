defmodule Regents.ProductActivity do
  @moduledoc """
  Tracks which folded Regent products currently have active route traffic so
  app-specific database reads, chain/Alchemy reads, and background pollers only
  run while that product's routes are actually in use.

  Every HTTP request and LiveView navigation touches the product named by its
  path (ignoring static assets, health checks, and static marketing/doc pages).
  Active timestamps live in a lock-free ETS table, replicated across cluster
  machines over `Regents.PubSub` (throttled to at most once a minute per
  product). Once a product has had no route traffic for its TTL (15 minutes by
  default), a local `{:product_idle, product}` notice lets its dormant shared
  readers cancel timers and drop cached readings until the next visit.
  """

  use GenServer

  @table __MODULE__
  @topic "product_activity"
  @products [:stake, :points, :keyfleet, :autolaunch, :patchbay, :techtree]
  @default_ttl_ms :timer.minutes(15)
  @broadcast_interval_ms :timer.minutes(1)
  @sweep_interval_ms :timer.minutes(5)
  @static_segments ~w(about docs skill.md agents.md llms.txt)

  @type product :: :stake | :points | :keyfleet | :autolaunch | :patchbay | :techtree

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc "The bounded list of products tracked for route-active gating."
  @spec products() :: [product()]
  def products, do: @products

  @doc "Subscribe to local `{:product_active, product}` and `{:product_idle, product}` notices."
  @spec subscribe() :: :ok
  def subscribe, do: Phoenix.PubSub.subscribe(Regents.PubSub, @topic)

  @doc """
  Marks `product` active now. Lock-free ETS write on every request; broadcasts to
  cluster peers and local subscribers immediately on wake and at most once per
  minute while active.
  """
  @spec touch(product()) :: :ok
  def touch(product) when product in @products do
    now = now_ms()
    was_active? = active_at?(product, now, ttl_ms())
    :ets.insert(@table, {product, now})

    if not was_active? or broadcast_due?(product, now) do
      :ets.insert(@table, {{:broadcast_at, product}, now})
      if not was_active?, do: report_active(product, 1)
      Phoenix.PubSub.broadcast(Regents.PubSub, @topic, {:product_active, product})
      ensure_sweep_running()
    end

    :ok
  rescue
    ArgumentError -> :ok
  end

  @doc """
  Touches the product(s) owning an active app route for `path`, if any.
  Health endpoints, static files, the home page, and static product marketing or
  doc pages activate nothing.
  """
  @spec touch_path(String.t() | nil) :: :ok
  def touch_path(path) when is_binary(path) do
    path
    |> path_only()
    |> products_for_path()
    |> Enum.each(&touch/1)
  end

  def touch_path(_other), do: :ok

  @doc "Maps a request path to the list of app products it activates (empty for non-app routes)."
  @spec products_for_path(String.t()) :: [product()]
  def products_for_path(path) when is_binary(path) do
    path |> String.split("/", trim: true) |> products_for_segments()
  end

  defp products_for_segments(["stake" | _]), do: [:stake]
  defp products_for_segments(["app"]), do: [:stake]

  defp products_for_segments(["api", "v1", seg | _]) when seg in ["stake", "staking"],
    do: [:stake]

  defp products_for_segments(["points" | _]), do: [:points]
  defp products_for_segments(["account" | _]), do: [:points]
  defp products_for_segments(["api", "v1", "account" | _]), do: [:points]
  defp products_for_segments(["api", "agents", "v1", "points" | _]), do: [:points]

  defp products_for_segments(["keyfleet", seg | _]) when seg not in @static_segments,
    do: [:keyfleet]

  defp products_for_segments(["api", "v1", "keyfleet" | _]), do: [:keyfleet]
  defp products_for_segments(["api", "agent", "v1", "keyfleet" | _]), do: [:keyfleet]

  defp products_for_segments(["autolaunch", seg | _]) when seg not in @static_segments,
    do: [:autolaunch]

  defp products_for_segments(["api", "v1", "autolaunch" | _]), do: [:autolaunch]
  defp products_for_segments(["api", "agent", "v1", "autolaunch" | _]), do: [:autolaunch]
  defp products_for_segments(["auth", "x" | _]), do: [:autolaunch]

  defp products_for_segments(["patchbay", seg | _]) when seg not in @static_segments,
    do: [:patchbay]

  defp products_for_segments(["api", "v1", "patchbay" | _]), do: [:patchbay]
  defp products_for_segments(["api", "agent", "v1", "patchbay" | _]), do: [:patchbay]
  defp products_for_segments(["api", "wallet-bench" | _]), do: [:patchbay]

  defp products_for_segments(["techtree", seg | _]) when seg not in @static_segments,
    do: [:techtree]

  defp products_for_segments(["api", "v1", "techtree" | _]), do: [:techtree]
  defp products_for_segments(["api", "agent", "v1", "techtree" | _]), do: [:techtree]
  defp products_for_segments(_other), do: []

  @doc "True when `product` has had route activity within `ttl_ms` (default 15 minutes)."
  @spec active?(atom(), pos_integer()) :: boolean()
  def active?(product, ttl \\ ttl_ms())

  def active?(product, ttl) when product in @products do
    active_at?(product, now_ms(), ttl)
  rescue
    ArgumentError -> false
  end

  def active?(_product, _ttl), do: false

  @doc """
  True when an Oban job is allowed to run for `product`: explicitly enqueued
  jobs (from a user action or `Regents.Chain.Refresh`) always run, while
  cron-scheduled periodic jobs only run while `product` is active.
  """
  @spec cron_allowed?(product(), Oban.Job.t()) :: boolean()
  def cron_allowed?(product, %Oban.Job{meta: %{"cron" => true}}), do: active?(product)
  def cron_allowed?(_product, %Oban.Job{}), do: true

  @doc "The products currently active within the configured TTL."
  @spec active_products() :: [product()]
  def active_products, do: Enum.filter(@products, &active?/1)

  @impl true
  def init(nil) do
    :ets.new(@table, [:named_table, :public, read_concurrency: true, write_concurrency: true])
    :ok = Phoenix.PubSub.subscribe(Regents.PubSub, @topic)
    Enum.each(@products, &report_active(&1, 0))
    {:ok, %{sweep_timer: nil}}
  end

  @impl true
  def handle_cast(:ensure_sweep, %{sweep_timer: nil} = state) do
    {:noreply, %{state | sweep_timer: Process.send_after(self(), :sweep, @sweep_interval_ms)}}
  end

  def handle_cast(:ensure_sweep, state), do: {:noreply, state}

  @impl true
  def handle_info({:product_active, product}, state) when product in @products do
    :ets.insert(@table, {product, now_ms()})
    report_active(product, 1)

    state =
      if is_nil(state.sweep_timer),
        do: %{state | sweep_timer: Process.send_after(self(), :sweep, @sweep_interval_ms)},
        else: state

    {:noreply, state}
  end

  def handle_info({:product_idle, _product}, state), do: {:noreply, state}

  def handle_info(:sweep, state) do
    now = now_ms()
    ttl = ttl_ms()

    remaining? =
      Enum.reduce(@products, false, fn product, any_left? ->
        case :ets.lookup(@table, product) do
          [{^product, last}] when now - last <= ttl ->
            true

          [{^product, _expired}] ->
            :ets.delete(@table, product)
            :ets.delete(@table, {:broadcast_at, product})
            report_active(product, 0)
            Phoenix.PubSub.local_broadcast(Regents.PubSub, @topic, {:product_idle, product})
            any_left?

          [] ->
            any_left?
        end
      end)

    timer = if remaining?, do: Process.send_after(self(), :sweep, @sweep_interval_ms)
    {:noreply, %{state | sweep_timer: timer}}
  end

  defp report_active(product, value) do
    :telemetry.execute([:regents, :product, :active], %{active: value}, %{product: product})
  end

  defp ensure_sweep_running do
    if pid = Process.whereis(__MODULE__), do: GenServer.cast(pid, :ensure_sweep)
  end

  defp active_at?(product, now, ttl) do
    case :ets.lookup(@table, product) do
      [{^product, last}] -> now - last <= ttl
      [] -> false
    end
  end

  defp broadcast_due?(product, now) do
    case :ets.lookup(@table, {:broadcast_at, product}) do
      [{_, last}] -> now - last >= @broadcast_interval_ms
      [] -> true
    end
  end

  defp path_only(path) do
    case String.split(path, "?", parts: 2) do
      [clean | _] -> clean
      [] -> path
    end
  end

  defp ttl_ms do
    Application.get_env(:regents, __MODULE__, [])
    |> Keyword.get(:ttl_ms, @default_ttl_ms)
  end

  defp now_ms, do: System.monotonic_time(:millisecond)
end
