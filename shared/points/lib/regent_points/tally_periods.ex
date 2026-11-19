defmodule RegentPoints.TallyPeriods do
  @moduledoc """
  Daily cron on the one designated owner site (Regents): queues one tally for each
  account that earned points in an ended season (a 30-day program period) and has no
  bonus for it yet. The last season is tallied like the others, after its end;
  nothing after it is. A tally that ran out of attempts is queued again by the next
  day's run.

  Every run ends with `[:regent_points, :tally_periods, :finished]`, measuring the
  tallies it queued (`accounts`), with the ended `periods` as metadata. It is emitted
  when there is nothing to queue too, so the site can tell when the cron last ran.
  """
  use Oban.Worker,
    queue: :points,
    max_attempts: 3,
    unique: [period: :infinity, states: :incomplete]

  require Ash.Query
  alias RegentPoints.{Account, Rules, Store, TallyAccount}

  @impl true
  def perform(_job) do
    program = Rules.program()
    periods = Rules.ended_periods(DateTime.utc_now())

    queued =
      for period <- periods, id <- untallied(program, period) do
        Oban.insert!(TallyAccount.new(%{program_id: program, account_id: id, period: period}))
      end

    :telemetry.execute(
      [:regent_points, :tally_periods, :finished],
      %{accounts: length(queued)},
      %{periods: periods}
    )

    :ok
  end

  defp untallied(program, period) do
    {start, stop} = Rules.period(period)

    query =
      Account
      |> Ash.Query.filter(
        exists(entries, program_id == ^program and earned_at >= ^start and earned_at < ^stop) and
          not exists(period_bonuses, program_id == ^program and period == ^period)
      )
      |> Ash.Query.select([:id])

    query
    |> then(&RegentPoints.read_accounts!(query: &1, actor: Store.system()))
    |> Enum.map(& &1.id)
  end
end
