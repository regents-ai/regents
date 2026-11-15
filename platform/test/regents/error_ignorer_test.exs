defmodule Regents.ErrorIgnorerTest do
  use ExUnit.Case, async: true

  alias Regents.ErrorIgnorer

  defp saved?(exception),
    do: not ErrorIgnorer.ignore?(%ErrorTracker.Error{kind: Atom.to_string(exception)}, %{})

  test "a connection the visitor closed is not saved" do
    refute saved?(Bandit.TransportError)
  end

  test "a wrong address is not saved, a server fault is" do
    refute saved?(Phoenix.Router.NoRouteError)
    refute saved?(Ash.Error.Invalid)
    assert saved?(RuntimeError)
    assert saved?(Ash.Error.Unknown)
  end

  test "a job attempt Oban will retry is not saved, its last one is" do
    error = %ErrorTracker.Error{kind: "Elixir.RuntimeError"}

    assert ErrorIgnorer.ignore?(error, %{state: :failure})
    refute ErrorIgnorer.ignore?(error, %{state: :discard})
  end
end
