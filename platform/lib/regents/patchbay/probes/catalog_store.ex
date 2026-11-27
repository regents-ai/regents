defmodule Regents.Patchbay.Probes.CatalogStore do
  @moduledoc """
  ETS-backed cache of live endpoint probe snapshots for Patchbay's curated
  commerce service catalog (`Regents.Patchbay.Commerce.Catalog`).

  Updated automatically by `Regents.Patchbay.Probes.CatalogWatch` (Oban cron)
  and synchronized across nodes via `Regents.PubSub`, with a bounded startup
  warm-up in serving environments so `/patchbay/app` and `/api/v1/patchbay/services`
  report real observed status, latency, and failing checks instead of static
  placeholders.
  """

  use GenServer

  @table :patchbay_catalog_probes
  @topic "patchbay:catalog_probes"
  @warmup_delay_ms 3_500

  @doc "PubSub topic notified whenever live catalog probe snapshots refresh."
  @spec topic() :: String.t()
  def topic, do: @topic

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Fetch the latest observed probe snapshot for a catalog service slug, or `nil`."
  @spec get(String.t()) :: map() | nil
  def get(slug) when is_binary(slug) do
    case :ets.whereis(@table) do
      :undefined ->
        nil

      _tid ->
        case :ets.lookup(@table, slug) do
          [{^slug, snapshot}] -> snapshot
          [] -> nil
        end
    end
  end

  def get(_other), do: nil

  @doc "Return all observed catalog probe snapshots keyed by service slug."
  @spec all_map() :: %{String.t() => map()}
  def all_map do
    case :ets.whereis(@table) do
      :undefined ->
        %{}

      _tid ->
        @table
        |> :ets.tab2list()
        |> Map.new()
    end
  end

  @doc "Store a map of `%{slug => snapshot}` locally and broadcast to peer nodes."
  @spec put_all(%{String.t() => map()}) :: :ok
  def put_all(snapshots) when is_map(snapshots) do
    write_local(snapshots)

    if Process.whereis(Regents.PubSub) do
      Phoenix.PubSub.broadcast(Regents.PubSub, @topic, {:catalog_probes_updated, snapshots})
    end

    :ok
  end

  @impl true
  def init(opts) do
    ensure_table()

    if Process.whereis(Regents.PubSub) do
      Phoenix.PubSub.subscribe(Regents.PubSub, @topic)
    end

    serving? = Keyword.get(opts, :serving?, false)

    if serving? and not Regents.read_only?() and
         Application.get_env(:regents, :folded_crons_enabled, true) do
      Process.send_after(self(), :warmup, @warmup_delay_ms)
    end

    {:ok, %{}}
  end

  @impl true
  def handle_info(:warmup, state) do
    if all_map() == %{} do
      Task.start(fn -> Regents.Patchbay.Probes.CatalogWatch.refresh_now() end)
    end

    {:noreply, state}
  end

  def handle_info({:catalog_probes_updated, snapshots}, state) when is_map(snapshots) do
    write_local(snapshots)
    {:noreply, state}
  end

  def handle_info(_other, state), do: {:noreply, state}

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])

      tid ->
        tid
    end
  end

  defp write_local(snapshots) do
    ensure_table()

    Enum.each(snapshots, fn {slug, snap} ->
      if is_binary(slug) and is_map(snap), do: :ets.insert(@table, {slug, snap})
    end)
  end
end
