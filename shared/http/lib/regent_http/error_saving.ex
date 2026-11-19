defmodule RegentHttp.ErrorSaving do
  @moduledoc """
  Keeps crash saving on when one save fails. ErrorTracker saves from inside its
  telemetry handlers, and telemetry removes for good a handler that raises, so one
  save that finds every database connection in use would leave later crashes unsaved
  until the next restart. ErrorTracker's handlers run through this one instead, where
  a save that fails is a single warning line.

  A site that uses ErrorTracker calls `attach/0` once at start:

      :ok = RegentHttp.ErrorSaving.attach()
  """

  require Logger

  @integrations [ErrorTracker.Integrations.Phoenix, ErrorTracker.Integrations.Oban]

  @doc "Takes over ErrorTracker's handlers, once, as the site starts."
  @spec attach() :: :ok
  def attach do
    Enum.each(@integrations, fn integration ->
      events =
        for %{id: ^integration, event_name: event} <- :telemetry.list_handlers([]), do: event

      :ok = :telemetry.detach(integration)
      :ok = :telemetry.attach_many(integration, events, &__MODULE__.handle_event/4, integration)
    end)
  end

  @doc false
  def handle_event(event, measurements, metadata, integration) do
    integration.handle_event(event, measurements, metadata, :no_config)
  catch
    kind, reason -> Logger.warning("Crash not saved: #{failure(kind, reason)}")
  end

  # The exception's name alone: its message can hold what the request carried.
  defp failure(_kind, %module{}), do: inspect(module)
  defp failure(kind, _reason), do: to_string(kind)
end
