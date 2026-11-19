defmodule RegentPoints.Reverse do
  @moduledoc "Auditable partial corrections; earning allowances never reopen; a tallied period's bonus follows."
  use Ash.Resource.Actions.Implementation
  require Ash.Query
  alias RegentPoints, as: Points
  alias RegentPoints.{Account, Entry, Store}
  @impl true
  def run(%{arguments: args}, _, _) do
    case Store.entry(args.entry_id) do
      %{reversal_of_entry_id: nil, points_micro_delta: points} = original when points > 0 ->
        Ash.transact(Account, fn ->
          Store.lock_account(original.account_id)
          correct(original, args)
        end)

      _ ->
        {:error, "Only a positive original award can be corrected"}
    end
  end

  defp correct(original, args) do
    key = "correction:" <> Store.digest({original.id, args.correction_key})

    case Store.award(original.program_id, key) do
      nil ->
        append(original, args, key)

      existing ->
        if existing.points_micro_delta == -args.points_micro and
             existing.reason_code == args.reason,
           do: %{id: existing.id},
           else: {:error, "Correction key conflicts with its original amount or reason"}
    end
  end

  defp append(original, args, key) do
    corrected =
      Entry
      |> Ash.Query.filter(reversal_of_entry_id == ^original.id)
      |> Ash.Query.for_read(:read, %{}, actor: Store.system())
      |> Ash.sum!(:points_micro_delta)

    reversed = -(corrected || 0)

    if reversed + args.points_micro > original.points_micro_delta do
      {:error, "Correction exceeds the original remaining award"}
    else
      attrs =
        original
        |> Map.from_struct()
        |> Map.take([
          :program_id,
          :account_id,
          :event_id,
          :rule_id,
          :rule_version,
          :source_app,
          :actor_kind,
          :actor_id,
          :category,
          :milestone_key
        ])

      row =
        Points.append_entry!(
          Map.merge(attrs, %{
            award_key: key,
            points_micro_delta: -args.points_micro,
            earned_at: original.earned_at,
            reversal_of_entry_id: original.id,
            reason_code: args.reason
          }),
          actor: Store.system()
        )

      Store.follow_period_bonus(row)
      %{id: row.id}
    end
  end
end
