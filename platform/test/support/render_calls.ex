defmodule RegentsWeb.RenderCalls do
  @moduledoc """
  Counts the renders a LiveView's server process runs, for checks that LiveView's
  change tracking leaves a part of the page alone when nothing in it changed. A
  function component LiveView does not call again sends the browser nothing.
  """

  @doc """
  How many times the process behind `view` called each one-argument function in
  `functions` (`{module, name}`) while `fun` ran.
  """
  def count(view, functions, fun) do
    mfas = for {module, name} <- functions, do: {module, name, 1}
    for mfa <- mfas, do: :erlang.trace_pattern(mfa, true, [:local])
    :erlang.trace(view.pid, true, [:call])
    fun.()
    :erlang.trace(view.pid, false, [:call])
    for mfa <- mfas, do: :erlang.trace_pattern(mfa, false, [:local])
    ref = :erlang.trace_delivered(view.pid)

    receive do
      {:trace_delivered, _pid, ^ref} -> collect(Map.new(functions, &{&1, 0}))
    end
  end

  defp collect(counts) do
    receive do
      {:trace, _pid, :call, {module, name, [_assigns]}} ->
        collect(Map.update!(counts, {module, name}, &(&1 + 1)))
    after
      0 -> counts
    end
  end
end
