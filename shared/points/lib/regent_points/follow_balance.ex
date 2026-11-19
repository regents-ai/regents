defmodule RegentPoints.FollowBalance do
  @moduledoc """
  Moves an account's stored total (`RegentPoints.Account` `balance_micro`) by what
  one ledger write added, inside that write's transaction: an entry's points, a new
  period bonus, or the change a bonus took when it followed the ledger. Every
  writer holds the account's lock (`RegentPoints.Store.lock_account/1`), so the
  bonus a follow starts from is the one saved.
  """
  use Ash.Resource.Change
  alias RegentPoints.{Entry, PeriodBonus, Store}

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn changeset, record ->
      case added(changeset, record) do
        0 -> :ok
        points -> RegentPoints.add_to_balance!(record.account_id, points, actor: Store.system())
      end

      {:ok, record}
    end)
  end

  @impl true
  def atomic(changeset, opts, context), do: {:ok, change(changeset, opts, context)}

  defp added(_changeset, %Entry{points_micro_delta: points}), do: points
  defp added(%{action_type: :create}, %PeriodBonus{bonus_micro: bonus}), do: bonus

  defp added(%{data: %PeriodBonus{bonus_micro: before}}, %PeriodBonus{bonus_micro: now}),
    do: now - before
end
