defmodule RegentsWeb.Techtree.Outage do
  @moduledoc """
  A page's database reads, with a lost connection or a refused read told apart
  from every other failure.

  A read that raised counts as an outage when it lost its connection to the
  database: the pool couldn't reach it, or Postgres ended the connection. That is
  never the page's own fault, so the page says it can't show its data right now
  instead of failing whole. It covers the seconds after a restart too, when each
  pooled connection fails once before the pool replaces it. On the read-only
  venue (`Regents.read_only?/0`) a read Postgres refused this login counts too:
  that login reads only the tables on its list (`priv/reader/grants.sql`), so a
  page whose tables are not on it says the same. On the live site a refused read
  is a missing grant and is raised as the fault it is. Anything else, a bug or a
  query error, is raised again unchanged, so it still shows as what it is. The
  failure is logged here, since the error tracker keeps its records in that same
  database: its kind and the database's code only, never the database's message,
  which can quote a query's values.
  """

  require Logger

  @spec read((-> value)) :: {:ok, value} | :database_down when value: term()
  def read(reads) do
    {:ok, reads.()}
  rescue
    error ->
      if outage?(error) do
        Logger.warning("Database read failed; page shows its outage note: " <> summary(error))

        :database_down
      else
        reraise error, __STACKTRACE__
      end
  end

  # A connection is lost when the pool can't reach the database, when the
  # connection itself fails (SQLSTATE class 08), or when Postgres ends it: a
  # restart or failover answers first with a shutdown, and a server still
  # starting with "cannot connect now" (class 57P). A read is refused with
  # insufficient_privilege (42501), an outage on the read-only venue alone.
  defp outage?(%DBConnection.ConnectionError{}), do: true
  defp outage?(%Postgrex.Error{postgres: %{pg_code: state}}), do: outage_state?(state)

  defp outage?(%Ash.Error.Unknown{errors: errors}),
    do: Enum.any?(errors, &outage?/1)

  # Ash keeps a data-layer failure only as its formatted text, which opens with
  # the exception's name and, for Postgres, the severity and SQLSTATE.
  defp outage?(%Ash.Error.Unknown.UnknownError{
         error: "** (DBConnection.ConnectionError)" <> _
       }),
       do: true

  defp outage?(%Ash.Error.Unknown.UnknownError{error: "** (Postgrex.Error) " <> text}) do
    case String.split(text, " ", parts: 3) do
      [_severity, state | _message] -> outage_state?(state)
      _other -> false
    end
  end

  defp outage?(_error), do: false

  # What is logged of an outage: the kind of failure and the SQLSTATE. A lost
  # connection's message is the pool's own words, which name no value.
  defp summary(%DBConnection.ConnectionError{message: message}),
    do: "DBConnection.ConnectionError: #{message}"

  defp summary(%Postgrex.Error{postgres: %{pg_code: state}}), do: "Postgrex.Error #{state}"

  defp summary(%Ash.Error.Unknown{errors: errors}),
    do: errors |> Enum.find(&outage?/1) |> summary()

  defp summary(%Ash.Error.Unknown.UnknownError{error: "** (DBConnection.ConnectionError)" <> _}),
    do: "DBConnection.ConnectionError"

  defp summary(%Ash.Error.Unknown.UnknownError{error: "** (Postgrex.Error) " <> text}) do
    [_severity, state | _message] = String.split(text, " ", parts: 3)
    "Postgrex.Error #{state}"
  end

  defp outage_state?("08" <> _connection_exception), do: true
  defp outage_state?("42501"), do: Regents.read_only?()
  defp outage_state?(state), do: state in ["57P01", "57P02", "57P03"]
end
