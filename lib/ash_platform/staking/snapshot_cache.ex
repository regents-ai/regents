defmodule AshPlatform.Staking.SnapshotCache do
  @moduledoc """
  The one contract reading every visitor to the staking pages is shown.

  A page paints this reading the moment it opens and asks Base for nothing.
  Only a signed-in visitor may ask for a new one, and when they do, the reading
  everyone sees is replaced at once rather than each page buying its own.

  A refusal here is never a failure: too soon after the last reading, or past
  the reading allowance for the minute, the last good reading simply stays. A
  reading that fails leaves the previous one exactly where it was.
  """

  use GenServer

  alias AshPlatform.Staking.ChainClient

  @topic "staking:protocol_snapshot"
  @minimum_interval_ms 10_000
  @window_ms 60_000
  @default_refreshes_per_minute 6
  @boot_attempts 6
  @default_boot_backoff_ms 2_000

  def start_link(_options), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @doc "The PubSub topic a new shared reading is announced on."
  def topic, do: @topic

  @doc "The last successful reading, or `nil` when Base has never answered."
  def snapshot, do: GenServer.call(__MODULE__, :snapshot)

  @doc """
  Asks for a new shared reading on behalf of `notify`.

  A caller that arrives while a reading is already running joins it rather than
  starting a second one. A successful reading reaches every subscribed page
  through `topic/0`; a failed one is reported only to the pages that asked.
  """
  def refresh(notify \\ self()) when is_pid(notify),
    do: GenServer.call(__MODULE__, {:refresh, notify})

  @doc false
  def clear, do: GenServer.call(__MODULE__, :clear)

  @doc "How many times the server tries for its own first reading before giving up."
  def boot_attempts, do: @boot_attempts

  @doc false
  def monotonic_ms, do: System.monotonic_time(:millisecond)

  @impl true
  def init(_options), do: {:ok, empty(), {:continue, :boot_read}}

  # The first reading is taken off to one side. Nothing waits for it: a page
  # that opens before it lands shows the unavailable state and offers a
  # signed-in visitor the control that takes one.
  #
  # An endpoint that is down exactly when the server starts would otherwise
  # leave every visitor looking at the unavailable state until some signed-in
  # person happened to arrive and ask, so the server keeps trying for its own
  # first reading a bounded number of times, waiting twice as long after each
  # failure. It stops the moment a reading exists, however that reading arrived.
  # These attempts are the server's own work and never spend the allowance that
  # bounds what visitors may ask for.
  @impl true
  def handle_continue(:boot_read, state), do: {:noreply, boot_read(state, 1)}

  @impl true
  def handle_call(:snapshot, _from, state), do: {:reply, state.snapshot, state}

  def handle_call(:clear, _from, state) do
    case state.in_flight do
      %{monitor: monitor} -> Process.demonitor(monitor, [:flush])
      nil -> :ok
    end

    {:reply, :ok, empty()}
  end

  def handle_call({:refresh, notify}, _from, %{in_flight: %{waiters: waiters} = read} = state),
    do: {:reply, :ok, %{state | in_flight: %{read | waiters: [notify | waiters]}}}

  def handle_call({:refresh, notify}, _from, state) do
    now = now()
    starts = Enum.filter(state.starts, &(&1 > now - @window_ms))

    if too_soon?(state.last_start, now) or length(starts) >= refreshes_per_minute() do
      {:reply, {:error, :refresh_too_soon}, %{state | starts: starts}}
    else
      {:reply, :ok,
       %{state | in_flight: start_read([notify]), starts: [now | starts], last_start: now}}
    end
  end

  @impl true
  def handle_info({:read, pid, result}, %{in_flight: %{pid: pid, monitor: monitor}} = state) do
    Process.demonitor(monitor, [:flush])
    {:noreply, settle(%{state | in_flight: nil}, state.in_flight, result)}
  end

  # A reading that died answered nothing about Base, so the pages waiting on it
  # are told so and the reading they already had is left alone.
  def handle_info(
        {:DOWN, monitor, :process, _pid, _reason},
        %{in_flight: %{monitor: monitor}} = state
      ) do
    {:noreply, settle(%{state | in_flight: nil}, state.in_flight, {:error, :unavailable})}
  end

  def handle_info({:boot_read, attempt}, state), do: {:noreply, boot_read(state, attempt)}

  def handle_info(_message, state), do: {:noreply, state}

  defp boot_read(state, attempt) do
    cond do
      not boot_read_enabled?() -> state
      not is_nil(state.snapshot) -> state
      is_nil(state.in_flight) -> %{state | in_flight: start_read([], attempt)}
      true -> %{state | in_flight: %{state.in_flight | boot_attempt: attempt}}
    end
  end

  # A visitor may already have a reading running when an attempt comes due.
  # Starting a second one would buy nothing, and simply giving up would end the
  # chain on somebody else's timing, so the attempt rides along with the reading
  # already in flight and arms the next attempt if that one fails.
  #
  # Only a reading the server started for itself, or joined this way, is
  # retried, and only while it has attempts left.
  defp retry_boot_read(nil), do: :ok
  defp retry_boot_read(attempt) when attempt >= @boot_attempts, do: :ok

  defp retry_boot_read(attempt) do
    Process.send_after(
      self(),
      {:boot_read, attempt + 1},
      boot_backoff_ms() * Integer.pow(2, attempt - 1)
    )

    :ok
  end

  defp settle(state, %{}, {:ok, snapshot}) do
    Phoenix.PubSub.broadcast(AshPlatform.PubSub, @topic, {:staking_snapshot, snapshot})
    %{state | snapshot: snapshot}
  end

  defp settle(state, read, {:error, reason}) do
    Enum.each(read.waiters, &send(&1, {:staking_snapshot_unavailable, reason}))
    retry_boot_read(read.boot_attempt)
    state
  end

  defp start_read(waiters, boot_attempt \\ nil) do
    server = self()

    {pid, monitor} =
      spawn_monitor(fn -> send(server, {:read, self(), safely_read()}) end)

    %{pid: pid, monitor: monitor, waiters: waiters, boot_attempt: boot_attempt}
  end

  defp safely_read do
    ChainClient.module().protocol_snapshot()
  rescue
    _ -> {:error, :unavailable}
  catch
    _, _ -> {:error, :unavailable}
  end

  defp too_soon?(nil, _now), do: false
  defp too_soon?(last_start, now), do: now - last_start < @minimum_interval_ms

  defp empty, do: %{snapshot: nil, in_flight: nil, starts: [], last_start: nil}

  defp boot_read_enabled?,
    do: Application.get_env(:ash_platform, :staking_snapshot_boot_read, false)

  defp boot_backoff_ms,
    do:
      max(
        Application.get_env(
          :ash_platform,
          :staking_snapshot_boot_backoff_ms,
          @default_boot_backoff_ms
        ),
        1
      )

  defp refreshes_per_minute,
    do:
      max(
        Application.get_env(
          :ash_platform,
          :staking_shared_refreshes_per_minute,
          @default_refreshes_per_minute
        ),
        0
      )

  defp now, do: clock().()

  defp clock,
    do: Application.get_env(:ash_platform, :staking_snapshot_clock, &__MODULE__.monotonic_ms/0)
end
