defmodule RegentPoints.Summary do
  @moduledoc "An owner-only read model containing no private source content or evidence URLs."
  use Ash.Resource.Actions.Implementation
  require Ash.Query
  alias RegentPoints, as: Points
  alias RegentPoints.{Account, CapUsage, Entry, Event, PeriodBonus, Rules, Seasons, Store}

  @impl true
  def run(input, _, %{actor: actor}) do
    id = actor.human_account_id

    account_query = Ash.Query.filter(Account, id == ^id)

    entries_query = Entry |> Ash.Query.filter(account_id == ^id) |> filters(input.arguments)
    today = DateTime.utc_now() |> DateTime.to_date()
    day_start = DateTime.new!(today, ~T[00:00:00])

    today_query =
      Entry
      |> Ash.Query.filter(account_id == ^id and earned_at >= ^day_start)
      |> Ash.Query.for_read(:read, %{}, actor: actor)

    yesterday_query =
      Entry
      |> Ash.Query.filter(
        account_id == ^id and earned_at >= ^DateTime.add(day_start, -1, :day) and
          earned_at < ^day_start
      )
      |> Ash.Query.for_read(:read, %{}, actor: actor)

    pending_query =
      Event
      |> Ash.Query.filter(account_id == ^id and processing_status == :pending)
      |> Ash.Query.for_read(:read, %{}, actor: Store.system())

    # Today's counts and allowances, and the one-time awards the account has had.
    cap_query =
      Ash.Query.filter(
        CapUsage,
        account_id == ^id and
          ((program_id == ^Rules.program() and window_start == ^today) or
             program_id == "lifetime")
      )

    bonuses_query =
      PeriodBonus |> Ash.Query.filter(account_id == ^id) |> Ash.Query.sort(period: :desc)

    with {:ok, accounts} <- Points.read_accounts(query: account_query, actor: actor),
         {:ok, period_bonuses} <- Points.read_period_bonuses(query: bonuses_query, actor: actor),
         {:ok, entries} <- Points.history(query: entries_query, actor: actor),
         {:ok, today_points} <- Ash.sum(today_query, :points_micro_delta),
         {:ok, yesterday_points} <- Ash.sum(yesterday_query, :points_micro_delta),
         {:ok, pending} <- Ash.count(pending_query),
         {:ok, caps} <- Points.read_caps(query: cap_query, actor: actor),
         {:ok, agent_names} <- agent_names(id, entries.results),
         balance = balance(List.first(accounts)),
         {:ok, place} <- place(balance) do
      {:ok,
       %{
         balance_micro: balance,
         place: place,
         earned_today_micro: today_points || 0,
         earned_yesterday_micro: yesterday_points || 0,
         pending: pending,
         entries: entries.results,
         period_bonuses: period_bonuses,
         current_period: current_period(id),
         agent_names: agent_names,
         more?: entries.more?,
         allowances: allowances(caps),
         done: done(caps)
       }}
    end
  end

  # The season running now; none before the first or after the last.
  defp current_period(id) do
    case Enum.find(Seasons.at(DateTime.utc_now()), &(&1.state == :running)) do
      %{season: period, ends_at: ends_at} ->
        %{
          number: period,
          ends_at: ends_at,
          earned_micro: Store.period_earned(id, Rules.program(), period)
        }

      nil ->
        nil
    end
  end

  defp agent_names(id, entries) do
    ids =
      entries
      |> Enum.filter(&(&1.actor_kind == "agent"))
      |> Enum.map(& &1.actor_id)
      |> Enum.uniq()

    RegentPoints.accounts().agent_names(id, ids)
  end

  defp balance(nil), do: 0
  defp balance(account), do: account.balance_micro

  # One more than the number of accounts with strictly more points, counted from
  # the board's index; none for an account without points. Every account's total
  # is counted, so this one count reads as the system.
  defp place(balance) when balance > 0 do
    above = Ash.Query.filter(Account, balance_micro > ^balance)
    with {:ok, count} <- Ash.count(above, actor: Store.system()), do: {:ok, count + 1}
  end

  defp place(_balance), do: {:ok, nil}

  # Only the daily allowances a rule earning right now counts against.
  defp allowances(caps) do
    Enum.map(
      Rules.active()
      |> Enum.map(&Rules.allowance_scope/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.sort(),
      fn scope ->
        used =
          case Enum.find(caps, &(&1.cap_scope == scope)) do
            nil -> 0
            cap -> cap.points_micro
          end

        limit = Rules.daily_cap(scope)
        %{scope: scope, limit: limit, remaining: max(0, limit - used)}
      end
    )
  end

  # For each listed rule, how many times the account has had its award inside the
  # rule's own window, on whichever site earned it: ever for a one-time rule, today
  # for a daily one; and whether this site earns it. The award reads the same rows
  # to decide what is left.
  defp done(caps) do
    counts = Map.new(caps, &{&1.cap_scope, &1.award_count})

    for %{"id" => id} = rule <- Rules.listed(), into: %{} do
      {id, %{times: Map.get(counts, Rules.count_scope(rule), 0), here: Rules.enabled?(id)}}
    end
  end

  defp filters(query, filters) do
    query =
      if filters[:source_app],
        do: Ash.Query.filter(query, source_app == ^filters.source_app),
        else: query

    if filters[:actor_kind],
      do: Ash.Query.filter(query, actor_kind == ^filters.actor_kind),
      else: query
  end
end
