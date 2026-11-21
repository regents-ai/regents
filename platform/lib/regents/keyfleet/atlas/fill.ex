defmodule Regents.Keyfleet.Atlas.Fill do
  @moduledoc """
  Every minute (`config :regents, Oban, cron:`): counts into the Atlas the
  graph changes each fleet copied beyond where its cursor says the Atlas has
  counted (`counted_seq` of `Regents.Keyfleet.Graph.Cursor`). That is all of them for
  a workspace copied before the Atlas began, and none once the projector
  counts each page as it copies it (`Regents.Keyfleet.Atlas.Count.copied/4`).

  The changes are read from the copied events, never from the graph itself,
  2,000 at a time, oldest first. Each batch is one transaction that holds the
  fleet's cursor, as a page the projector copies does, counts the batch and
  moves the counted place past it, or to the end of the copied log once
  nothing is left. A run stops taking batches after 40 seconds and the next
  run carries on from there, so a year of history is counted over a few runs
  and no run outlasts its minute. Each batch tells the fleet's Atlas readers
  (`Regents.Keyfleet.Atlas.changed/1`).
  """
  use Oban.Worker,
    queue: :keyfleet_default,
    max_attempts: 1,
    unique: [period: :infinity, states: :incomplete]

  alias Regents.Keyfleet.{Atlas, Graph}
  alias Regents.Keyfleet.Atlas.Count

  @system %Regents.Account.Actors.System{}
  @budget_ms 40_000
  @batch 2_000
  @tables [Graph.Cursor, Graph.Event, Graph.Object, Atlas.Thing, Atlas.Bucket]

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    until = System.monotonic_time(:millisecond) + @budget_ms

    Enum.reduce_while(Graph.uncounted_cursors!(actor: @system), :ok, fn cursor, :ok ->
      if fill(cursor.fleet_id, until) == :caught_up, do: {:cont, :ok}, else: {:halt, :ok}
    end)
  end

  # Batches of the fleet until it is caught up or the run's time is spent.
  defp fill(fleet_id, until) do
    case batch(fleet_id) do
      {:ok, :caught_up} ->
        :caught_up

      {:ok, :counted} ->
        Atlas.changed(fleet_id)

        if System.monotonic_time(:millisecond) < until,
          do: fill(fleet_id, until),
          else: :out_of_time
    end
  end

  @doc """
  Counts the fleet's next batch: answers `{:ok, :counted}` once it has, or
  `{:ok, :caught_up}` when the Atlas had already counted the copied log.
  """
  def batch(fleet_id) do
    Ash.transact(@tables, fn ->
      case Graph.hold_cursor!(fleet_id, actor: @system) do
        %{counted_seq: counted, applied_seq: applied} = cursor when counted < applied ->
          events = Graph.changes_after!(fleet_id, counted, actor: @system)
          Count.count_graph(fleet_id, Enum.map(events, &logged/1), types(fleet_id, events))
          Graph.mark_counted!(cursor, %{counted_seq: counted_to(events, applied)}, actor: @system)
          :counted

        _counted_or_gone ->
          :caught_up
      end
    end)
  end

  # Past the batch, or to the end of the copied log once the batch was its last.
  defp counted_to(events, applied) when length(events) < @batch, do: applied
  defp counted_to(events, _applied), do: List.last(events).seq

  # A copied event as the log gave it.
  defp logged(event) do
    %{
      "seq" => event.seq,
      "type" => event.type,
      "actor" => event.actor,
      "timestamp" => event.timestamp,
      "payload" => event.payload,
      "projects" => event.projects
    }
  end

  # The types of the items the batch patches, as the read tables hold them.
  defp types(fleet_id, events) do
    targets =
      for %{type: "patch.applied", payload: %{"patch" => %{"target" => id}}} <- events,
          uniq: true,
          do: id

    fleet_id
    |> Graph.read_objects!(targets, actor: @system)
    |> Map.new(&{&1.id, &1.type})
  end
end
