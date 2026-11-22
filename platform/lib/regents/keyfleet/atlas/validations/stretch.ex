defmodule Regents.Keyfleet.Atlas.Validations.Stretch do
  @moduledoc """
  A stretch of the swarm runs forward, `from` before `to`, and holds at most
  1,000 buckets of its span, so one read is always small: about six weeks of
  hours, nearly three years of days, or nineteen years of weeks.
  """
  use Ash.Resource.Validation

  @most 1_000
  @hours %{hour: 1, day: 24, week: 168, month: 744, year: 8_784}

  @impl true
  def supports(_opts), do: [Ash.ActionInput]

  @impl true
  def validate(input, _opts, _context) do
    %{span: span, from: from, to: to} = input.arguments

    cond do
      DateTime.compare(from, to) != :lt ->
        {:error, field: :to, message: "must come after from"}

      DateTime.diff(to, from, :hour) > @most * @hours[span] ->
        {:error, field: :to, message: "must be at most #{@most} buckets after from"}

      true ->
        :ok
    end
  end
end
