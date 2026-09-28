defmodule Regents.EnsLookups do
  @moduledoc """
  Every sign-in starts an ENS lookup that nothing waits for. A test that signs
  in lets those lookups finish before its database closes.
  """

  import ExUnit.Assertions
  import ExUnit.Callbacks

  @doc "A `setup` step: at the test's end, wait for the ENS lookups it started."
  def await_at_exit(_context) do
    # Registered after the case's sandbox setup, so it runs before the owner stops.
    on_exit(fn ->
      for pid <- Task.Supervisor.children(Regents.Ens.TaskSupervisor) do
        ref = Process.monitor(pid)
        assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 2_000
      end
    end)
  end
end
