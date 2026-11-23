defmodule Regents.Patchbay.Forum.CatalogSync do
  @moduledoc """
  Runs Patchbay's idempotent WebMCP catalog sync (`Catalog.sync!/0` and
  `ProgramSites.make!/0`) at most once per boot, lazily on the first active
  Patchbay route rather than during application startup.
  """

  use GenServer

  alias Regents.Patchbay.Forum
  alias Regents.ProductActivity

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(nil) do
    ProductActivity.subscribe()
    {:ok, %{synced?: false}}
  end

  @impl true
  def handle_info({:product_active, :patchbay}, %{synced?: false} = state) do
    if not Regents.read_only?() do
      Task.start(fn ->
        # Keep routine idempotent catalog upserts from flooding dev debug logs;
        # warnings and errors still log normally.
        Logger.put_process_level(self(), :info)
        Forum.Catalog.sync!()
        Forum.ProgramSites.make!()
      end)
    end

    {:noreply, %{state | synced?: true}}
  end

  def handle_info({:product_active, _product}, state), do: {:noreply, state}
  def handle_info({:product_idle, _product}, state), do: {:noreply, state}
end
