defmodule AshPlatform.SandboxRace do
  @moduledoc """
  Sends several callers at one row at the same moment.

  A test case owns a single sandboxed database connection, and every caller the
  case spawns borrows that one connection. The callers therefore take turns
  rather than run in parallel: each one holds the connection for as long as its
  own statement or transaction lasts, and the others wait. What the barrier
  proves is that two callers arriving at the same step in either order still
  produce the one outcome the row itself decided.

  Every caller reports in before any of them is released, so none of them can
  finish its work before the rest have even started.
  """

  # A caller that is waiting its turn on the shared connection can be held up
  # for as long as the caller ahead of it takes, which on a busy machine is far
  # longer than the work itself. The wait is bounded by the connection pool, so
  # this only has to outlast it.
  @await_timeout :timer.seconds(30)

  @doc """
  Runs `work` from `count` callers released together, and returns their results.
  """
  def race(work, count), do: race_each(List.duplicate(work, count))

  @doc """
  Runs each function in `works` from its own caller, all released together.

  Results come back in the order the functions were given.
  """
  def race_each(works) do
    barrier = :erlang.unique_integer()
    parent = self()

    works
    |> Enum.map(&waiting_caller(&1, parent, barrier))
    |> release(barrier)
    |> Task.await_many(@await_timeout)
  end

  defp waiting_caller(work, parent, barrier) do
    Task.async(fn ->
      send(parent, {:ready, barrier, self()})

      receive do
        {:go, ^barrier} -> work.()
      end
    end)
  end

  defp release(callers, barrier) do
    ready =
      for _caller <- callers do
        receive do
          {:ready, ^barrier, pid} -> pid
        end
      end

    Enum.each(ready, &send(&1, {:go, barrier}))

    callers
  end
end
