defmodule Regents.Account.Points.Board do
  @moduledoc """
  The Points board every signed-in reader shares (`RegentPoints.leaderboard/1`),
  read once for all of them and held in `Regents.SharedReading` under `key/0`.
  One runs on each machine. Ported from ash-template's `AshTemplate.Points.Board`.

  It hears every award, correction and period bonus on this site
  (`points:board`) and reads the board again, at most once a second however many
  arrive. It holds nothing but whether a read is due: no queue, no copy of rows,
  and it never writes the database.

  An award on another Regent site changes the shared totals without a notice
  here, and a notice can be lost, so each minute `Regents.SharedReading.Heal`
  asks for the board to be read again.

  The reading holds the ten highest rows with their account ids, highest first.
  Pages and the agent's answer keep the ids on the server: a reader gets the rows
  without ids and a mark on their own row, and their own place comes with their
  own summary (`RegentsWeb.Account.PointsEntries`). A board too large for its kind is
  refused and marked degraded, and the last one stays shown as behind.

  The first read happens as it starts, so the key holds a reading or its
  degraded mark before the site serves a page.
  """

  use GenServer

  alias Regents.ProductActivity
  alias Regents.SharedReading

  @kind :points_board

  @doc "Where the board of this site's Points program is held."
  def key, do: {@kind, RegentPoints.Rules.program()}

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil)

  @impl true
  def init(nil) do
    SharedReading.register_producer(@kind, self(), :sync)
    SharedReading.subscribe_heal(@kind)
    ProductActivity.subscribe()
    Phoenix.PubSub.subscribe(Regents.PubSub, "points:board")
    {:ok, %{due: false, loaded?: false}}
  end

  @impl true
  def handle_call(:ensure_loaded, _from, %{loaded?: true} = state), do: {:reply, :ok, state}

  def handle_call(:ensure_loaded, _from, state) do
    ProductActivity.touch(:points)
    read()
    SharedReading.mark_loaded(@kind, true)
    {:reply, :ok, %{state | due: false, loaded?: true}}
  end

  @impl true
  def handle_info({:product_idle, :points}, %{loaded?: true} = state) do
    SharedReading.mark_loaded(@kind, false)
    SharedReading.clear_kind(@kind)
    {:noreply, %{state | due: false, loaded?: false}}
  end

  def handle_info({:product_idle, _product}, state), do: {:noreply, state}
  def handle_info({:product_active, _product}, state), do: {:noreply, state}

  def handle_info(%{topic: "points:board"}, %{loaded?: true} = state),
    do: {:noreply, due(state)}

  def handle_info(%{topic: "points:board"}, state), do: {:noreply, state}

  def handle_info({:shared_reading_heal, @kind}, %{loaded?: true} = state) do
    if ProductActivity.active?(:points), do: {:noreply, due(state)}, else: {:noreply, state}
  end

  def handle_info({:shared_reading_heal, @kind}, state), do: {:noreply, state}

  def handle_info(:read, %{due: true, loaded?: true} = state) do
    if ProductActivity.active?(:points), do: read()
    {:noreply, %{state | due: false}}
  end

  def handle_info(:read, state), do: {:noreply, %{state | due: false}}

  @doc "Reads the board now and holds it, or marks it not read."
  def read do
    with {:ok, board} <- board(),
         :ok <- SharedReading.put(key(), board) do
      :ok
    else
      {:error, _not_held} -> SharedReading.degraded(key())
    end
  end

  # The first notice starts the one-second wait; the rest join it.
  defp due(%{due: true} = state), do: state

  defp due(%{due: false} = state) do
    Process.send_after(self(), :read, 1_000)
    %{state | due: true}
  end

  defp board do
    RegentPoints.leaderboard(actor: RegentPoints.Store.system())
  rescue
    # The database not answering raises beneath Ash. It is a read not taken,
    # never a reason for this process, and the site with it, to stop.
    error in [DBConnection.ConnectionError, Postgrex.Error] -> {:error, error}
  end
end
