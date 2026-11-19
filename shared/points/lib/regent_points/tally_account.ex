defmodule RegentPoints.TallyAccount do
  @moduledoc """
  Writes one account's bonus for one ended 30-day program period: the points earned
  in that period times the tier its linked wallets held at the period-end snapshot. An action
  checked or corrected after the tally moves the bonus at the saved tier
  (`RegentPoints.Store.follow_period_bonus/1`). Oban retries a Base outage.
  """
  use Oban.Worker,
    queue: :points_chain,
    max_attempts: 10,
    unique: [keys: [:program_id, :account_id, :period], period: :infinity, states: :incomplete]

  require Ash.Query
  alias RegentPoints, as: Points
  alias RegentPoints.{Account, Bonus, PeriodBonus, Rules, Snapshot, Store}

  @impl true
  def perform(%Oban.Job{args: %{"account_id" => id, "period" => period} = args}) do
    # Base is read before the transaction; the account lock then guards the write.
    program = Map.get(args, "program_id", Rules.program())
    tally(id, period, program)
  end

  @doc "Tallies one period from its fixed snapshot; `now` supports deterministic operator verification."
  def tally(id, period, program, now \\ DateTime.utc_now()) do
    with {:ok, snapshot} <- Snapshot.for_period(program, period, now),
         {:ok, tier} <- Bonus.at_snapshot(id, snapshot),
         {:ok, _} <- Ash.transact(Account, fn -> record(id, period, tier, snapshot) end) do
      :ok
    end
  end

  defp record(id, period, tier, snapshot) do
    Store.lock_account(id)
    program = Rules.program()

    existing =
      PeriodBonus
      |> Ash.Query.filter(program_id == ^program and account_id == ^id and period == ^period)
      |> then(&Points.read_period_bonuses!(query: &1, actor: Store.system()))

    if existing == [] do
      earned = Store.period_earned(id, program, period)

      Points.record_period_bonus!(
        %{
          program_id: program,
          account_id: id,
          period: period,
          snapshot_id: snapshot.id,
          earned_micro: earned,
          nft_count: tier.nft_count,
          nft_block: tier.block,
          bonus_percent: tier.percent,
          bonus_micro: div(earned * tier.percent, 100)
        },
        actor: Store.system()
      )
    end

    :ok
  end
end
