defmodule RegentHttp.UnexpectedFailure do
  @moduledoc """
  Logs failure classes without request content or exception values: one line for
  a request answered "try again", and one line for a background job that has run
  out of attempts. A job's earlier attempts log nothing, so a job that recovers on
  a retry leaves no error line.

  Each line names the error's module, up to four immediate causes and, for a
  request, a SHA-256 fingerprint of the request id. Error messages, request
  bodies and job arguments never reach the log.

  A site calls `attach_jobs/0` once at start, and `log/2` wherever a request is
  answered "try again":

      UnexpectedFailure.attach_jobs()

      conn |> UnexpectedFailure.log(error) |> send_try_again()
  """

  require Logger

  @doc "Logs each job that gives up, from Oban's own event; called once at start."
  @spec attach_jobs() :: :ok | {:error, :already_exists}
  def attach_jobs,
    do:
      :telemetry.attach(
        "regent-http-job-gave-up",
        [:oban, :job, :exception],
        &__MODULE__.job_failed/4,
        nil
      )

  @doc false
  def job_failed(_event, _measurements, %{state: :discard, job: job, reason: error}, _config) do
    Logger.error(
      "Job gave up: worker=#{job.worker} id=#{job.id} attempt=#{job.attempt} class=#{class(error)} causes=#{causes(error)}"
    )
  end

  def job_failed(_event, _measurements, _metadata, _config), do: :ok

  @doc "Logs bounded error classes and a hashed request correlation; returns `conn`."
  @spec log(conn, term()) :: conn when conn: Plug.Conn.t()
  def log(conn, error) do
    # The line carries only the hashed correlation, never the raw request id or
    # an error type inherited from the process's metadata.
    Logger.error(
      "Request answered try again: class=#{class(error)} causes=#{causes(error)} correlation=#{correlation()}",
      request_id: nil,
      error_type: nil
    )

    conn
  end

  defp class(%{__struct__: module}) when is_atom(module),
    do: module |> Atom.to_string() |> String.slice(0, 128)

  defp class(_error), do: "unclassified"

  # Only immediate classes, with no recursive inspection of wrapped errors.
  defp causes(%{errors: errors}) when is_list(errors),
    do: errors |> Enum.take(4) |> Enum.map_join(",", &class/1)

  defp causes(_error), do: "none"

  defp correlation do
    case Logger.metadata()[:request_id] do
      id when is_binary(id) and byte_size(id) <= 128 ->
        :crypto.hash(:sha256, id) |> Base.encode16(case: :lower)

      _ ->
        "unavailable"
    end
  end
end
