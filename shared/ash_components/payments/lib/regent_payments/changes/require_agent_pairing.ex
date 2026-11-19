defmodule RegentPayments.Changes.RequireAgentPairing do
  @moduledoc false
  use Ash.Resource.Change
  alias RegentPayments.AgentAuthority

  @impl true
  def change(changeset, opts, %{actor: actor}) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      case check(opts[:mode], changeset, actor) do
        :ok -> changeset
        {:error, error} -> Ash.Changeset.add_error(changeset, error)
      end
    end)
  end

  defp check(:prepare, changeset, actor) do
    prepared = %{
      actor_profile_id: Ash.Changeset.get_attribute(changeset, :actor_profile_id),
      payload: Ash.Changeset.get_attribute(changeset, :payload),
      payload_digest: Ash.Changeset.get_attribute(changeset, :payload_digest)
    }

    with true <- actor != nil and prepared.actor_profile_id == Map.get(actor, :id),
         :ok <- AgentAuthority.unchanged_authority(actor, prepared),
         {:ok, snapshot} <- AgentAuthority.from_actor(actor) do
      if snapshot, do: AgentAuthority.lock(snapshot), else: :ok
    else
      _ -> AgentAuthority.refused()
    end
  end

  defp check(:settle, changeset, actor) do
    with {:ok, fresh} <- RegentPayments.lock_payment_intent(changeset.data.id, actor: actor) do
      initial_transition(actor, changeset.data, fresh)
    end
  end

  defp check(:immutable, changeset, actor) do
    with :ok <- frozen(changeset), do: unchanged(changeset, actor)
  end

  defp frozen(changeset) do
    if Enum.any?(Map.keys(changeset.attributes), &(&1 not in [:status, :updated_at])) do
      {:error,
       Ash.Error.Changes.InvalidChanges.exception(message: "frozen payment terms cannot change")}
    else
      :ok
    end
  end

  defp unchanged(changeset, %{role: :payment_completion} = actor) do
    with {:ok, fresh} <- RegentPayments.lock_payment_intent(changeset.data.id, actor: actor) do
      if completion_transition?(changeset.action.name, fresh.status) and
           AgentAuthority.completion_for?(actor, fresh, fresh.kind),
         do: :ok,
         else: AgentAuthority.refused()
    end
  end

  defp unchanged(changeset, actor), do: AgentAuthority.unchanged_authority(actor, changeset.data)

  defp initial_transition(_actor, %{status: :settlement_pending}, %{status: :settlement_pending}),
    do: :ok

  defp initial_transition(actor, %{status: status}, %{status: status} = fresh)
       when status in [:prepared, :payment_required, :failed],
       do: AgentAuthority.current(actor, fresh)

  defp initial_transition(_, _, _), do: AgentAuthority.refused()
  defp completion_transition?(:mark_settlement_pending, :settlement_pending), do: true
  defp completion_transition?(:mark_settled, :settlement_pending), do: true
  defp completion_transition?(:mark_applied, :settled), do: true
  defp completion_transition?(:mark_failed, :settlement_pending), do: true
  defp completion_transition?(_, _), do: false
end
