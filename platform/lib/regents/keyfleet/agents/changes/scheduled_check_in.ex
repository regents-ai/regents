defmodule Regents.Keyfleet.Agents.Changes.ScheduledCheckIn do
  @moduledoc """
  Records a scheduled check-in, counts it as a return when it comes on
  time, and keeps the count that confirms the schedule, all in the one
  statement that inserts or updates the row.

  With `I` the declared interval and `gap` the time since the counted
  scheduled check-in:

    * a new interval, or no counted check-in yet, starts a new count;
    * a gap under half the interval is too soon: it is a check-in, but not a
      step in the count;
    * a gap of at most the interval plus the grace confirms the schedule;
    * a gap of at most twice the interval plus the grace counts and leaves the
      confirmation as it was;
    * a longer gap means the check-ins had stopped, so confirming starts again.

  A return is the first scheduled check-in or one at least half its interval
  after the counted one, whatever interval it names, so checking in more often
  than the schedule, or naming a new interval each time, never adds returns.
  """
  use Ash.Resource.Change

  require Ash.Expr

  alias Regents.Keyfleet.Agents.CheckInStatus

  @impl true
  def change(changeset, _opts, _context) do
    minutes = Ash.Changeset.get_argument(changeset, :every_minutes)
    grace = CheckInStatus.grace_minutes()

    changeset
    |> Ash.Changeset.atomic_set(:last_check_in_at, now())
    |> Ash.Changeset.atomic_set(:last_scheduled_at, now())
    |> Ash.Changeset.atomic_set(:counted_scheduled_at, now())
    |> Ash.Changeset.atomic_update(:last_check_in_at, now())
    |> Ash.Changeset.atomic_update(:last_scheduled_at, now())
    |> Ash.Changeset.atomic_set(:scheduled_check_ins, 1)
    |> Ash.Changeset.atomic_update(
      :scheduled_check_ins,
      Ash.Expr.expr(
        type(
          fragment(
            """
            CASE
              WHEN ? IS NULL
                OR (statement_timestamp() AT TIME ZONE 'utc') - ? >= make_interval(mins => ?::integer) / 2
                THEN ? + 1
              ELSE ?
            END
            """,
            counted_scheduled_at,
            counted_scheduled_at,
            ^minutes,
            scheduled_check_ins,
            scheduled_check_ins
          ),
          :integer
        )
      )
    )
    |> Ash.Changeset.atomic_update(
      :counted_scheduled_at,
      Ash.Expr.expr(
        type(
          fragment(
            """
            CASE
              WHEN ? IS DISTINCT FROM ?::integer OR ? IS NULL
                THEN (statement_timestamp() AT TIME ZONE 'utc')
              WHEN (statement_timestamp() AT TIME ZONE 'utc') - ? < make_interval(mins => ?::integer) / 2
                THEN ?
              ELSE (statement_timestamp() AT TIME ZONE 'utc')
            END
            """,
            schedule_minutes,
            ^minutes,
            counted_scheduled_at,
            counted_scheduled_at,
            ^minutes,
            counted_scheduled_at
          ),
          :utc_datetime_usec
        )
      )
    )
    |> Ash.Changeset.atomic_update(
      :schedule_confirmed_at,
      Ash.Expr.expr(
        type(
          fragment(
            """
            CASE
              WHEN ? IS DISTINCT FROM ?::integer OR ? IS NULL
                THEN NULL
              WHEN (statement_timestamp() AT TIME ZONE 'utc') - ? < make_interval(mins => ?::integer) / 2
                THEN ?
              WHEN (statement_timestamp() AT TIME ZONE 'utc') - ? <= make_interval(mins => ?::integer + ?::integer)
                THEN COALESCE(?, (statement_timestamp() AT TIME ZONE 'utc'))
              WHEN (statement_timestamp() AT TIME ZONE 'utc') - ? <= make_interval(mins => 2 * ?::integer + ?::integer)
                THEN ?
              ELSE NULL
            END
            """,
            schedule_minutes,
            ^minutes,
            counted_scheduled_at,
            counted_scheduled_at,
            ^minutes,
            schedule_confirmed_at,
            counted_scheduled_at,
            ^minutes,
            ^grace,
            schedule_confirmed_at,
            counted_scheduled_at,
            ^minutes,
            ^grace,
            schedule_confirmed_at
          ),
          :utc_datetime_usec
        )
      )
    )
  end

  defp now,
    do:
      Ash.Expr.expr(
        type(fragment("(statement_timestamp() AT TIME ZONE 'utc')"), :utc_datetime_usec)
      )
end
