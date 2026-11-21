defmodule Regents.Keyfleet.Graph.Projector do
  @moduledoc """
  Keeps one fleet's workspace read tables copied from its graph log.

  Two things make it copy: a write that has just been applied asks it to
  reach that write's place in the log (`await/3`), and every
  `:catch_up_interval` it copies whatever the log holds beyond its cursor
  anyway. The second is what makes the first only a hint: a request that is
  lost, or a copy that failed, is made good on the next round from the
  cursor, which is kept with the tables. A copy that fails is logged and
  tried again on the next round; nothing that goes wrong stops the projector.
  Copies failing for longer than a new host takes to start are a stall, saved
  once with the site's errors (`Regents.Keyfleet.Graph.StalledError`) until a copy succeeds.

  It remembers which log, and how far along it, the tables reached last; a
  place in one log says nothing about another. Each time that changes, once
  the copy is committed, it says so through the database
  (`Regents.Keyfleet.Graph.Notices`), which the site repeats to the fleet's members on
  `Regents.Keyfleet.Graph.head_topic/1`, and, when what was copied holds a change the
  fleet's activity shows anyone, or the log started over, on
  `Regents.Keyfleet.Graph.notable_topic/1`.

  Each projector is found by its fleet in the `Regents.Keyfleet.Graph.Processes`
  registry of the machine it runs on, as the writers are.
  """
  use GenServer

  require Logger

  alias Regents.Keyfleet.Graph
  alias Regents.Keyfleet.Graph.{Notices, Projection, StalledError}

  # Twice the longest a new graph host takes to replay its log and answer
  # (`:hello_timeout`), so a host starting after a deploy is no stall.
  @stall_ms 120_000

  def child_spec(opts) do
    %{id: {__MODULE__, Keyword.fetch!(opts, :fleet_id)}, start: {__MODULE__, :start_link, [opts]}}
  end

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: name(Keyword.fetch!(opts, :fleet_id)))

  defp name(fleet_id),
    do: {:via, Registry, {Regents.Keyfleet.Graph.Processes, {__MODULE__, fleet_id}}}

  @doc """
  Waits, up to `:projection_wait`, until the fleet's read tables reach `seq`
  in the log named `run_id`, the place a write just reached, so a read made
  after the write answers finds it.

  Answers how far along that log the tables are known to have reached, 0 when
  none of it is known to be copied. A projector that is not running, or not
  there in time, leaves the write to the next round; the write stands either
  way.
  """
  @spec await(String.t(), String.t(), non_neg_integer()) :: non_neg_integer()
  def await(fleet_id, run_id, seq) do
    GenServer.call(name(fleet_id), {:await, run_id, seq}, wait())
  catch
    :exit, _reason -> 0
  end

  @doc "The longest `await/3` waits."
  @spec wait() :: pos_integer()
  def wait,
    do: Keyword.fetch!(Application.fetch_env!(:regents, :keyfleet_graph), :projection_wait)

  @impl true
  def init(opts) do
    state = %{
      fleet_id: Keyword.fetch!(opts, :fleet_id),
      interval: Keyword.fetch!(opts, :catch_up_interval),
      run_id: nil,
      watermark: 0,
      failing_since: nil,
      stall_reported?: false
    }

    {:ok, state, {:continue, :catch_up}}
  end

  @impl true
  def handle_continue(:catch_up, state), do: {:noreply, scheduled_round(state)}

  @impl true
  def handle_info(:catch_up, state), do: {:noreply, scheduled_round(state)}

  @impl true
  def handle_call({:await, run_id, seq}, _from, %{run_id: run_id, watermark: watermark} = state)
      when watermark >= seq,
      do: {:reply, watermark, state}

  def handle_call({:await, run_id, _seq}, _from, state) do
    state = catch_up(state)
    {:reply, reached(state, run_id), state}
  end

  defp reached(%{run_id: run_id, watermark: watermark}, run_id), do: watermark
  defp reached(_state, _run_id), do: 0

  defp scheduled_round(state) do
    Process.send_after(self(), :catch_up, state.interval)
    catch_up(state)
  end

  defp catch_up(state) do
    case copy(state.fleet_id) do
      {:ok, {run_id, watermark}} ->
        if {run_id, watermark} != {state.run_id, state.watermark},
          do: announce(state, run_id, watermark)

        %{
          state
          | run_id: run_id,
            watermark: watermark,
            failing_since: nil,
            stall_reported?: false
        }

      {:error, reason} ->
        Logger.warning(
          "copying the workspace of #{state.fleet_id} stopped (#{short(reason)}); " <>
            "the next round resumes it"
        )

        failed(state, reason)
    end
  end

  defp failed(%{failing_since: nil} = state, _reason),
    do: %{state | failing_since: System.monotonic_time(:millisecond)}

  defp failed(%{stall_reported?: false} = state, reason) do
    if System.monotonic_time(:millisecond) - state.failing_since > @stall_ms do
      StalledError.report(
        "The workspace of #{state.fleet_id} has not caught up with its log for over " <>
          "two minutes (#{short(reason)}); pages show it as it last was"
      )

      %{state | stall_reported?: true}
    else
      state
    end
  end

  defp failed(state, _reason), do: state

  defp announce(%{fleet_id: fleet_id} = state, run_id, watermark) do
    Notices.head(fleet_id, run_id, watermark)

    if run_id != state.run_id or notable_since?(fleet_id, state.watermark),
      do: Notices.notable(fleet_id)
  end

  # Whether the newest change the activity shows anyone was copied after
  # `watermark`. A notice is only a hint, so a read that fails sends none.
  defp notable_since?(fleet_id, watermark),
    do:
      match?(
        {:ok, [%{seq: seq}]} when seq > watermark,
        Graph.notable_before(fleet_id, nil, 1)
      )

  # The kind of failure only: the same one repeats every round until it clears.
  defp short(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp short({reason, _detail}) when is_atom(reason), do: Atom.to_string(reason)
  defp short(%{__exception__: true} = exception), do: inspect(exception.__struct__)
  defp short(_reason), do: "unexpected reply"

  # A database failure mid-copy leaves the cursor at the last page that
  # committed, so the next round simply resumes there.
  defp copy(fleet_id) do
    Projection.catch_up(fleet_id)
  rescue
    exception -> {:error, exception}
  end
end
