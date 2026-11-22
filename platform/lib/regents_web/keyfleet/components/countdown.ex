defmodule RegentsWeb.Keyfleet.Components.Countdown do
  @moduledoc """
  The time something open has left, such as a poll or a proposal's vote, or
  the time until something starts, such as a new Key's share of the Treasury
  slice. The page writes it as of `now`; the browser writes it again as it changes, from
  the closing time and the gap between its own clock and the site's
  (`assets/js/keyfleet/hooks/countdown.ts`), in the same words, so a phone whose clock
  is wrong still counts down to the right moment.
  """
  use Phoenix.Component

  attr :id, :string, required: true
  attr :closes_at, DateTime, required: true
  attr :now, DateTime, required: true, doc: "the site's clock as the page read what closes"

  attr :format, :string,
    required: true,
    values: ~w(hours minutes seconds clock),
    doc:
      "`hours` above an hour, then minutes; `minutes` alone; a clock's minutes and seconds; " <>
        "or `clock`, hours, minutes and seconds after `lead`, then `done`"

  attr :lead, :string, default: nil, doc: "a `clock`'s words before its time"

  attr :done, :string,
    default: nil,
    doc:
      "the words once its time runs out; without them a `clock` writes none, and the others their last count"

  attr :class, :string, default: nil

  def countdown(assigns) do
    ~H"""
    <span
      id={@id}
      class={@class}
      phx-hook="Countdown"
      data-closes-at={DateTime.to_unix(@closes_at, :millisecond)}
      data-now={DateTime.to_unix(@now, :millisecond)}
      data-format={@format}
      data-lead={@lead}
      data-done={@done}
    >{words(assigns, DateTime.diff(@closes_at, @now, :second))}</span>
    """
  end

  defp words(%{done: done}, seconds) when seconds <= 0 and is_binary(done), do: done
  defp words(%{format: "clock"}, seconds) when seconds <= 0, do: nil

  defp words(%{format: "clock", lead: lead}, seconds),
    do:
      "#{lead} #{pad(div(seconds, 3600))}:#{seconds |> div(60) |> rem(60) |> pad()}:#{seconds |> rem(60) |> pad()}"

  defp words(%{format: format}, seconds), do: left(format, seconds)

  defp left("hours", seconds) when seconds >= 3600,
    do: "#{count(div(seconds, 3600), "hour", "hours")} left"

  defp left(format, seconds) when format in ~w(hours minutes) and seconds < 60,
    do: "Less than a minute left"

  defp left(format, seconds) when format in ~w(hours minutes),
    do: "#{count(div(seconds, 60), "minute", "minutes")} left"

  defp left("seconds", seconds) when seconds <= 0, do: "Closing…"

  defp left("seconds", seconds) when seconds < 60,
    do: "#{count(seconds, "second", "seconds")} left"

  defp left("seconds", seconds), do: "#{div(seconds, 60)}:#{seconds |> rem(60) |> pad()} left"

  defp pad(number), do: number |> Integer.to_string() |> String.pad_leading(2, "0")

  defp count(1, one, _many), do: "1 #{one}"
  defp count(number, _one, many), do: "#{number} #{many}"
end
