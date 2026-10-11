defmodule Regents.PaperProDaily.Publication do
  @moduledoc "Read-time publication at the start of a paper's date in UTC."
  use Ash.Resource.Preparation

  require Ash.Query

  # The test build supplies a controlled clock. Releases compile with DateTime;
  # request parameters and runtime settings cannot replace the server clock.
  @clock Application.compile_env(:regents, :paper_publication_clock, DateTime)

  def today, do: @clock.utc_now() |> DateTime.shift_zone!("Etc/UTC") |> DateTime.to_date()

  @impl true
  def prepare(query, _opts, _context), do: published_query(query)

  @doc "Filters by the server's current UTC date; an explicit instant supports boundary tests."
  def published_query(query, now \\ @clock.utc_now()) do
    today = now |> DateTime.shift_zone!("Etc/UTC") |> DateTime.to_date()
    Ash.Query.filter(query, date <= ^today)
  end

  @doc "Milliseconds until the next UTC midnight, never scheduling before a sub-millisecond boundary."
  def milliseconds_until_midnight(now \\ @clock.utc_now()) do
    midnight =
      now
      |> DateTime.shift_zone!("Etc/UTC")
      |> DateTime.to_date()
      |> Date.add(1)
      |> DateTime.new!(~T[00:00:00], "Etc/UTC")

    # Round up, rather than waking just before midnight and showing the old day.
    microseconds = DateTime.diff(midnight, now, :microsecond)
    div(microseconds + 999, 1_000)
  end
end
