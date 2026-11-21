defmodule Regents.Keyfleet.Atlas.Span do
  @moduledoc """
  The lengths of time the Atlas counts by, in UTC: an hour, a day, a week
  (from Monday), a month and a year. A span's bucket is named by its `start/2`,
  and runs to `next/2`.
  """
  use Ash.Type.Enum, values: [:hour, :day, :week, :month, :year]

  @doc "Every span, shortest first."
  def all, do: values()

  @doc "The start of the `span` holding `at`, in UTC."
  def start(:hour, %DateTime{} = at), do: %{at | minute: 0, second: 0, microsecond: {0, 0}}
  def start(:day, %DateTime{} = at), do: midnight(DateTime.to_date(at))

  def start(:week, %DateTime{} = at),
    do: at |> DateTime.to_date() |> Date.beginning_of_week(:monday) |> midnight()

  def start(:month, %DateTime{} = at),
    do: at |> DateTime.to_date() |> Date.beginning_of_month() |> midnight()

  def start(:year, %DateTime{} = at), do: midnight(Date.new!(at.year, 1, 1))

  @doc "The start of the bucket after the one starting at `start`."
  def next(:hour, start), do: DateTime.add(start, 1, :hour)
  def next(:day, start), do: DateTime.add(start, 1, :day)
  def next(:week, start), do: DateTime.add(start, 7, :day)
  def next(:month, start), do: start |> DateTime.to_date() |> Date.shift(month: 1) |> midnight()
  def next(:year, start), do: start |> DateTime.to_date() |> Date.shift(year: 1) |> midnight()

  defp midnight(date), do: DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
end
