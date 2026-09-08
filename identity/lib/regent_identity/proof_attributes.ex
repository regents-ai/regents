defmodule RegentIdentity.ProofAttributes do
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

    changeset = Ash.Changeset.force_change_attributes(changeset, attributes)

    changeset =
      if changeset.action_type == :create do
        wallet =
          case actor.wallet_addresses do
            [one] -> one
            _ -> nil
          end

        Ash.Changeset.force_change_attribute(changeset, :wallet_address, wallet)
      else
        changeset
      end

    Ash.Changeset.before_action(changeset, fn locked ->
      RegentIdentity.lock(actor)

      case RegentIdentity.get_my_profile(actor: actor) do
        {:ok, nil} ->
          locked

        {:ok, current} ->
          locked = validate_freshness(locked, current, actor, attributes)

          if locked.action_type == :update and current.id == locked.data.id do
            # Equality was measured against the caller's old record; apply the
            # complete proof against the locked current row instead.
            %{locked | data: current}
            |> Ash.Changeset.force_change_attributes(attributes)
          else
            locked
          end

        {:error, error} ->
          Ash.Changeset.add_error(locked, error)
      end
    end)
  end

  def change(changeset, _, _),
    do: Ash.Changeset.add_error(changeset, "verified identity required")

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
