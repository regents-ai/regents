defmodule RegentIdentity.ProofAttributes do
  @moduledoc """
  Writes the verified Privy proof onto a profile, and refuses evidence older
  than, or conflicting with, the proof already saved.
  """
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, %{actor: %RegentPrivy.Session{} = actor}) do
    x = Enum.find(actor.linked_socials, &(&1.provider == :x)) || %{}

    attributes = %{
      app_id: actor.app_id,
      privy_user_id: actor.privy_user_id,
      wallet_addresses: actor.wallet_addresses,
      x_subject: x[:subject],
      x_username: x[:username],
      x_display_name: x[:display_name],
      proof_issued_at: actor.issued_at
    }

    changeset
    |> Ash.Changeset.force_change_attributes(attributes)
    |> initial_wallet(actor)
    |> Ash.Changeset.before_action(&against_current(&1, actor, attributes))
  end

  def change(changeset, _, _),
    do: Ash.Changeset.add_error(changeset, "verified identity required")

  defp initial_wallet(%{action_type: :create} = changeset, actor) do
    wallet =
      case actor.wallet_addresses do
        [one] -> one
        _ -> nil
      end

    Ash.Changeset.force_change_attribute(changeset, :wallet_address, wallet)
  end

  defp initial_wallet(changeset, _actor), do: changeset

  defp against_current(locked, actor, attributes) do
    RegentIdentity.lock(actor)

    case RegentIdentity.get_my_profile(actor: RegentIdentity.Owner.of(actor)) do
      {:ok, nil} ->
        locked

      {:ok, current} ->
        locked
        |> validate_freshness(current, actor, attributes)
        |> onto_current(current, attributes)

      {:error, error} ->
        Ash.Changeset.add_error(locked, error)
    end
  end

  # Equality was measured against the caller's old record; apply the complete
  # proof against the locked current row instead.
  defp onto_current(
         %{action_type: :update, data: %{id: id}} = locked,
         %{id: id} = current,
         attributes
       ),
       do: Ash.Changeset.force_change_attributes(%{locked | data: current}, attributes)

  defp onto_current(locked, _current, _attributes), do: locked

  defp validate_freshness(changeset, current, actor, attributes) do
    same =
      MapSet.new(current.wallet_addresses) == MapSet.new(actor.wallet_addresses) and
        Enum.all?(
          [:x_subject, :x_username, :x_display_name],
          &(Map.get(current, &1) == attributes[&1])
        )

    if not is_integer(actor.issued_at) or actor.issued_at < current.proof_issued_at or
         (actor.issued_at == current.proof_issued_at and not same) do
      Ash.Changeset.add_error(changeset,
        field: :proof_issued_at,
        message: "stale or conflicting identity evidence"
      )
    else
      changeset
    end
  end
end
