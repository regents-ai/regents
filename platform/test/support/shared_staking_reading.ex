defmodule Regents.SharedStakingReading do
  @moduledoc """
  The shared staking reading in tests.

  The refresh job saves the reading; on a running server
  `Regents.Staking.SnapshotListener` hears Postgres announce the commit and
  tells this machine's pages. The test sandbox never commits, so `run/0` tells
  the pages itself, with the listener's own messages.
  """

  alias Regents.Actors.System
  alias Regents.Staking
  alias Regents.Staking.{SnapshotCache, SnapshotRefresh}

  @doc "Runs the refresh job once, as Oban would, and tells open pages how it ended."
  def run do
    case Oban.Testing.perform_job(SnapshotRefresh, %{key: SnapshotCache.key()},
           repo: Regents.Repo
         ) do
      :ok ->
        snapshot = SnapshotCache.snapshot()
        broadcast({:staking_snapshot, snapshot})
        {:ok, snapshot}

      {:error, _reason} = error ->
        broadcast({:staking_snapshot_unavailable, :unavailable})
        error

      {:snooze, _seconds} = snooze ->
        snooze
    end
  end

  @doc "Takes a new reading now, whenever the last one was taken."
  def share do
    age()
    {:ok, snapshot} = run()
    snapshot
  end

  @doc "Makes the saved reading old enough that the next refresh reads Base again."
  def age do
    case Staking.get_protocol_reading(SnapshotCache.key(), actor: %System{}) do
      {:ok, nil} ->
        :ok

      {:ok, saved} ->
        {:ok, _aged} =
          Staking.replace_protocol_reading(
            saved,
            %{snapshot: Map.put(saved.snapshot, "read_at", "2000-01-01T00:00:00Z")},
            actor: %System{}
          )

        :ok
    end
  end

  defp broadcast(message),
    do: Phoenix.PubSub.broadcast(Regents.PubSub, SnapshotCache.topic(), message)
end
