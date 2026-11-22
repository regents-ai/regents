defmodule RegentsWeb.Keyfleet.PageRead do
  @moduledoc """
  A page's own read, done while the page is drawn: the read that finishes
  inside the callback in the ash-template repository's
  `skills/ash-frontend/references/async-state.md`. A failed database read
  (`Postgrex.Error`, `DBConnection.ConnectionError`, or the `Ash.Error.Unknown`
  an Ash read wraps either in) comes back as `{:error, failure}`, so the page
  says it couldn't be loaded rather than crashing. The failure is logged as an
  error with its kind and the database's code and name for it (or the pool's
  words for a lost connection), never the query or the values in it, and saved with the site's errors (`Regents.Alert.save/3`), so a read that
  keeps failing is seen at /admin/errors. The save runs beside the page, which
  never waits on it, and only so many run at once (`Regents.Keyfleet.ErrorSaves`):
  while the database can't be reached the saves fail too, and `/healthz`
  already says so. An address that names nothing still raises
  `RegentsWeb.NotFoundError`.
  """

  require Logger

  @spec run(String.t(), (-> value)) :: {:ok, value} | {:error, Exception.t()} when value: term()
  def run(page, read) do
    {:ok, read.()}
  rescue
    failure in [Postgrex.Error, DBConnection.ConnectionError, Ash.Error.Unknown] ->
      Logger.error("Reading the #{page} page failed: " <> summary(failure))
      stacktrace = __STACKTRACE__
      context = ErrorTracker.get_context()

      Task.Supervisor.start_child(Regents.Keyfleet.ErrorSaves, fn ->
        Regents.Alert.save(failure, stacktrace, context)
      end)

      {:error, failure}
  end

  # A Postgrex error's message carries the query and the row's values, the
  # database's own one-line reason can quote a value too, and an Ash error's
  # carries the whole query it ran, so only the kind of failure and the
  # database's code and name for it are logged. A lost connection's message
  # is the pool's own words, which name no value.
  defp summary(%Ash.Error.Unknown{errors: [%{error: %_{} = cause} | _]}), do: summary(cause)

  defp summary(%Postgrex.Error{postgres: %{pg_code: code, code: name}}),
    do: "Postgrex.Error #{code} (#{name})"

  defp summary(%DBConnection.ConnectionError{message: message}),
    do: "DBConnection.ConnectionError: #{message}"

  defp summary(%module{}), do: inspect(module)
end
