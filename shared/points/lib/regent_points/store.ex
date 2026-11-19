defmodule RegentPoints.Store do
  @moduledoc false
  require Ash.Query
  alias RegentPoints, as: Points
  alias RegentPoints.{Account, CapUsage, Entry, Event, PeriodBonus, Rules}
  @system %{role: :system}

  def system, do: @system

  def digest(value),
    do:
      :crypto.hash(:sha256, :erlang.term_to_binary(value, [:deterministic]))
      |> Base.encode16(case: :lower)

  # Lock one canonical account for all of its awards and corrections. Cap rows
  # alone cannot serialize two different rules sharing one daily allowance.
  def lock_account(id) do
    Points.open_account!(%{id: id}, actor: @system)
    query = Account |> Ash.Query.filter(id == ^id) |> Ash.Query.lock(:for_update)
    Points.read_accounts!(query: query, actor: @system) |> List.first()
  end

  # The private audit of a refused source reference, at intake or at the award. It
  # survives Oban pruning and never overwrites a previously accepted event.
  def reject_source(reference, reason) do
    Points.reject_source!(
      %{
        source: reference,
        reason_code: to_string(reason),
        rejection_key: digest({reference, reason})
      },
      actor: @system
    )
  end

  def event(id) do
    query = Ash.Query.filter(Event, id == ^id)
    Points.read_events!(query: query, actor: @system) |> List.first()
  end

  def entry(id) do
    Points.read_entries!(query: Ash.Query.filter(Entry, id == ^id), actor: @system)
    |> List.first()
  end

  def award(program, key) do
    query = Ash.Query.filter(Entry, program_id == ^program and award_key == ^key)
    Points.read_entries!(query: query, actor: @system) |> List.first()
  end

  @doc "The points an account earned in one program period, summed in the database."
  def period_earned(account_id, program, period) do
    {start, stop} = Rules.period(period)

    Entry
    |> Ash.Query.filter(
      account_id == ^account_id and program_id == ^program and earned_at >= ^start and
        earned_at < ^stop
    )
    |> Ash.Query.for_read(:read, %{}, actor: @system)
    |> Ash.sum!(:points_micro_delta)
    |> Kernel.||(0)
    |> max(0)
  end

  # Called under the account lock with every new entry. A period already tallied
  # keeps the tier saved at its tally; its earned total and bonus follow the ledger,
  # so a late award or a correction moves the bonus with it.
  def follow_period_bonus(entry) do
    period = Rules.period_of(entry.earned_at)

    query =
      Ash.Query.filter(
        PeriodBonus,
        program_id == ^entry.program_id and account_id == ^entry.account_id and
          period == ^period
      )

    case Points.read_period_bonuses!(query: query, actor: @system) do
      [bonus] ->
        earned = period_earned(entry.account_id, entry.program_id, period)

        Points.follow_period_bonus!(
          bonus,
          %{earned_micro: earned, bonus_micro: div(earned * bonus.bonus_percent, 100)},
          actor: @system
        )

      [] ->
        nil
    end
  end

  def cap(account_id, program, scope, {start, stop}) do
    row =
      Points.reserve_cap!(
        %{
          account_id: account_id,
          program_id: program,
          cap_scope: scope,
          window_start: start,
          window_end: stop
        },
        actor: @system
      )

    query = CapUsage |> Ash.Query.filter(id == ^row.id) |> Ash.Query.lock(:for_update)
    Points.read_caps!(query: query, actor: @system) |> List.first()
  end

  def human(id) do
    RegentPoints.accounts().human(id)
  end

  def wallets(account) do
    [account.wallet_address | List.wrap(account.wallet_addresses)]
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.downcase/1)
    |> Enum.uniq()
    |> Enum.sort()
  end
end
