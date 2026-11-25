defmodule Regents.ErrorIgnorer do
  @moduledoc """
  Leaves out an exception the site answers below 500, such as not found or a bad
  request. Anyone can raise those by visiting a wrong address, so saving them
  would let anyone fill the table. A connection the visitor closed while a page
  was being sent is left out for the same reason. Server faults, exits and throws
  are all kept.

  A job attempt that Oban will retry is left out too: ErrorTracker reports each
  failed attempt with Oban's `state`, which is `:failure` while attempts remain
  and `:discard` on the last one. A job that recovers on a later attempt saves
  nothing, and one that runs out of attempts is saved once.
  """

  @behaviour ErrorTracker.Ignorer

  # Oban.PerformError wrapping Keyfleet's HubSilentError when no notebook hub
  # connection came free; the wait is already saved where it happened.
  @hub_wait ~r/\A\S+ failed with \{:error, \{:hub, "(?:[^"\\]|\\.)*", %Regents\.Keyfleet\.Notebooks\.HubSilentError\{message: "(?:[^"\\]|\\.)*"\}\}\}\z/

  @impl ErrorTracker.Ignorer
  def ignore?(_error, %{state: :failure}), do: true

  def ignore?(%ErrorTracker.Error{kind: "Elixir.Oban.PerformError", reason: reason}, _context)
      when is_binary(reason),
      do: Regex.match?(@hub_wait, reason)

  def ignore?(%ErrorTracker.Error{kind: "Elixir." <> _module = kind}, _context),
    do: kind |> String.to_existing_atom() |> visitors?()

  def ignore?(_error, _context), do: false

  # Ash's four error classes take their status from the errors they wrap, so the
  # class names whose doing it was: bad input or a refusal, or a server fault.
  defp visitors?(class) when class in [Ash.Error.Invalid, Ash.Error.Forbidden], do: true
  defp visitors?(class) when class in [Ash.Error.Unknown, Ash.Error.Framework], do: false

  # A visitor who closes the tab or loses the connection while a page is being
  # sent: nothing on the site failed, and anyone can do it at will.
  defp visitors?(Bandit.TransportError), do: true

  defp visitors?(exception),
    do:
      Code.ensure_loaded?(exception) and function_exported?(exception, :exception, 1) and
        Plug.Exception.status(exception.__struct__()) < 500
end
