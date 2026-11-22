defmodule Regents.Keyfleet.Agents.CheckInStatus do
  @moduledoc """
  What an agent's check-ins with a fleet say about it, derived only from when
  they arrived (`Regents.Keyfleet.Agents.CheckIn`), never from anything the agent says
  about itself.

  The rules, checked in order:

    1. No check-in recorded: `:never_checked_in`.
    2. A check-in during a conversation at most 120 seconds ago:
       `:connected_now`.
    3. A schedule declared, and no scheduled check-in for more than twice its
       interval plus 45 minutes: `:paused`.
    4. A schedule confirmed by two scheduled check-ins about one interval
       apart: `:check_ins_working`.
    5. A schedule declared but not yet confirmed: `:confirming_schedule`.
    6. Otherwise: `:no_schedule`.
  """

  # A check-in during a conversation this recent means the agent is there now.
  @connected_seconds 120
  # Each kind of check-in, and each contribution, is written at most this often.
  @spacing_seconds 60
  # How late a scheduled check-in may be and still count.
  @grace_minutes 45
  # The intervals a schedule may declare, in minutes.
  @schedule_minutes 10..1440

  @labels %{
    never_checked_in: "Hasn’t checked in",
    connected_now: "Connected now",
    paused: "Paused",
    check_ins_working: "Check-ins working",
    confirming_schedule: "Waiting for a second scheduled check-in",
    no_schedule: "No scheduled check-ins"
  }

  @doc "How often each kind of check-in, and each contribution, is written at most, in seconds."
  def spacing_seconds, do: @spacing_seconds

  @doc "How late, in minutes, a scheduled check-in may be and still count."
  def grace_minutes, do: @grace_minutes

  @doc "The intervals, in minutes, a schedule may declare."
  def schedule_minutes, do: @schedule_minutes

  @doc """
  The status of an agent whose check-ins with a fleet are `check_in` (`nil`
  when it has never checked in there), at `now`: `{status, label}`.
  """
  def derive(nil, _now), do: status(:never_checked_in)

  def derive(check_in, now) do
    cond do
      within?(check_in.last_session_at, now, @connected_seconds) ->
        status(:connected_now)

      check_in.schedule_minutes != nil and
          not within?(
            check_in.last_scheduled_at,
            now,
            (2 * check_in.schedule_minutes + @grace_minutes) * 60
          ) ->
        status(:paused)

      check_in.schedule_confirmed_at != nil ->
        status(:check_ins_working)

      check_in.schedule_minutes != nil ->
        status(:confirming_schedule)

      true ->
        status(:no_schedule)
    end
  end

  @doc """
  Whether scheduled check-ins are repeating at `now`: the schedule is
  confirmed and the last scheduled check-in is no older than twice its
  interval plus 45 minutes, whatever a conversation is doing.
  """
  def repeating?(nil, _now), do: false

  def repeating?(check_in, now) do
    check_in.schedule_confirmed_at != nil and
      within?(
        check_in.last_scheduled_at,
        now,
        (2 * check_in.schedule_minutes + @grace_minutes) * 60
      )
  end

  @doc """
  The light shown beside the agent, from the same check-ins: `:on` (green)
  when it is connected now or its scheduled check-ins arrive on time, `:late`
  (amber) when it checks in but no schedule is confirmed or the latest
  scheduled check-in is overdue, and `:off` (red) when it is paused or has
  never checked in.
  """
  def light(check_in, now) do
    case derive(check_in, now) do
      {status, _label} when status in [:never_checked_in, :paused] ->
        :off

      {:connected_now, _label} ->
        :on

      {:check_ins_working, _label} ->
        if within?(
             check_in.last_scheduled_at,
             now,
             (check_in.schedule_minutes + @grace_minutes) * 60
           ),
           do: :on,
           else: :late

      {_checked_in, _label} ->
        :late
    end
  end

  defp status(status), do: {status, Map.fetch!(@labels, status)}

  defp within?(nil, _now, _seconds), do: false

  defp within?(at, now, seconds),
    do: DateTime.diff(now, at, :microsecond) <= seconds * 1_000_000
end
