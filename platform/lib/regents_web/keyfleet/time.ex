defmodule RegentsWeb.Keyfleet.Time do
  @moduledoc """
  Times as people read them on a page. A message's time is drawn with
  `local/1`: the server writes it in UTC, and once the page is live the
  reader's browser writes it again in their own time zone, with today and
  yesterday by their own calendar (the `LocalTime` hook).
  """
  use Phoenix.Component

  @doc """
  When `at` was, as seen on `now`'s day: "Today 14:03 UTC", "Yesterday 09:10
  UTC", then the day alone, "22 Sep", with its year when that is not this
  year's, "22 Sep 2025".
  """
  def moment(%DateTime{} = at, %DateTime{} = now) do
    days = Date.diff(DateTime.to_date(now), DateTime.to_date(at))

    cond do
      days == 0 -> Calendar.strftime(at, "Today %H:%M UTC")
      days == 1 -> Calendar.strftime(at, "Yesterday %H:%M UTC")
      at.year == now.year -> Calendar.strftime(at, "%-d %b")
      true -> Calendar.strftime(at, "%-d %b %Y")
    end
  end

  @doc """
  When `at` was, short enough for a line of a feed: "14:03" today, then
  "Yesterday", then the day as `moment/2` gives it.
  """
  def clock(%DateTime{} = at, %DateTime{} = now) do
    case Date.diff(DateTime.to_date(now), DateTime.to_date(at)) do
      0 -> Calendar.strftime(at, "%H:%M")
      1 -> "Yesterday"
      _days -> moment(at, now)
    end
  end

  attr :id, :string, required: true
  attr :at, DateTime, required: true
  attr :as, :atom, required: true, values: [:clock, :moment, :stamp, :date]
  attr :title_as, :atom, default: nil, values: [nil, :moment], doc: "how its hover title says it"
  attr :class, :string, default: nil

  @doc """
  `at` in a `<time>`, as `as` writes it: `:clock` and `:moment` as their
  functions here, `:stamp` as "20 October 2026 at 14:03 UTC", `:date` as
  "20 Oct 2026". The reader's browser writes it again in their own time zone.
  """
  def local(assigns) do
    ~H"""
    <time
      id={@id}
      class={@class}
      phx-hook="LocalTime"
      datetime={DateTime.to_iso8601(@at)}
      data-as={@as}
      data-title-as={@title_as}
      title={@title_as && words(@title_as, @at)}
    >{words(@as, @at)}</time>
    """
  end

  defp words(:clock, at), do: clock(at, DateTime.utc_now())
  defp words(:moment, at), do: moment(at, DateTime.utc_now())
  defp words(:stamp, at), do: Calendar.strftime(at, "%-d %B %Y at %H:%M UTC")
  defp words(:date, at), do: Calendar.strftime(at, "%-d %b %Y")
end
