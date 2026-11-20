defmodule Regents.Alert do
  @moduledoc """
  Saves something a person has to act on with the site's errors (ErrorTracker,
  shown to the site's admins at /admin/errors). A job that only logs, or ends
  cancelled, saves nothing there, so these would otherwise go unseen.

  ErrorTracker keeps one error per place in the code, so each line that reports
  is its own error, listing every occurrence with its own message. Reporting it
  again while it is still listed adds an occurrence and marks it unresolved
  again. `Regents.ErrorPruner` clears an error a week after it was last seen.

  The errors are kept in the site's own database, so a save fails while the
  database can't be reached. A failed save is logged and never raises: the
  caller carries on, and `/healthz` already says the database is down.
  """

  require Logger

  @doc """
  Saves `exception`, placed at the line that called its module's report
  function. That call must not be the caller's last: a last call leaves no line
  of the caller to find.
  """
  @spec report(Exception.t()) :: :ok
  def report(%module{} = exception) do
    {:current_stacktrace, stacktrace} = Process.info(self(), :current_stacktrace)

    save(exception, Enum.drop_while(stacktrace, &(elem(&1, 0) in [Process, __MODULE__, module])))
  end

  defp save(exception, stacktrace) do
    ErrorTracker.report(exception, stacktrace)
    :ok
  catch
    kind, reason -> unsaved(exception, Exception.format_banner(kind, reason))
  end

  defp unsaved(exception, why) do
    Logger.error(
      "An error couldn't be saved with the site's errors (#{why}): " <>
        Exception.message(exception)
    )

    :ok
  end
end
