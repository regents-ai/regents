defmodule Regents.PaperProDaily.Publication do
  @moduledoc "Read-time publication at the start of a paper's date in UTC."
  use Ash.Resource.Preparation

  require Ash.Query

  @impl true
  def prepare(query, _opts, _context) do
    today = Date.utc_today()
    Ash.Query.filter(query, date <= ^today)
  end

  @doc "Milliseconds until the next UTC midnight, never scheduling before a sub-millisecond boundary."
  def milliseconds_until_midnight do
    now = DateTime.utc_now()
    midnight = now |> DateTime.to_date() |> Date.add(1) |> DateTime.new!(~T[00:00:00], "Etc/UTC")

    # Round up, rather than waking just before midnight and showing the old day.
    microseconds = DateTime.diff(midnight, now, :microsecond)
    div(microseconds + 999, 1_000)
  end
end
