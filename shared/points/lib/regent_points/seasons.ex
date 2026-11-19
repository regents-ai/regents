defmodule RegentPoints.Seasons do
  @moduledoc """
  The seasons Points runs in, as every site shows them: program periods 1 to
  `RegentPoints.Rules.season_count/0`, 30 days each, one after the other from the
  start (`RegentPoints.Rules.period/1`). Season `n` is period `n`, so its NFT bonus
  is that period's. Nothing done after the last season's end earns.

  Before a start is set every season is upcoming and has no dates.
  """

  alias RegentPoints.Rules

  @day 86_400

  @doc """
  Every season as it stands at `now`, first to last: `%{season, starts_at,
  ends_at, state, days_left}`. `state` is `:upcoming`, `:running` or `:ended`;
  `days_left` is the whole days to the running season's end, the last part day
  counting as one, and nil for the others.
  """
  def at(now) do
    start = Rules.config()[:starts_at]
    for season <- 1..Rules.season_count(), do: season(season, start, now)
  end

  @doc "Where Points stands: `:before` the first season, `:running`, or `:ended` after the last."
  def phase(seasons) do
    cond do
      Enum.any?(seasons, &(&1.state == :running)) -> :running
      Enum.all?(seasons, &(&1.state == :ended)) -> :ended
      true -> :before
    end
  end

  defp season(season, nil, _now),
    do: %{season: season, starts_at: nil, ends_at: nil, state: :upcoming, days_left: nil}

  defp season(season, _start, now) do
    {starts_at, ends_at} = Rules.period(season)

    state =
      cond do
        DateTime.before?(now, starts_at) -> :upcoming
        DateTime.before?(now, ends_at) -> :running
        true -> :ended
      end

    %{
      season: season,
      starts_at: starts_at,
      ends_at: ends_at,
      state: state,
      days_left: if(state == :running, do: div(DateTime.diff(ends_at, now) + @day - 1, @day))
    }
  end
end
