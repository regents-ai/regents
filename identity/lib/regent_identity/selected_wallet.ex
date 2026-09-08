defmodule RegentIdentity.SelectedWallet do
  use Ash.Resource.Change
  @impl true
  def change(changeset, _opts, %{actor: %RegentPrivy.Session{} = actor}) do
    changeset =
      case Ash.Changeset.get_attribute(changeset, :display_name) do
        name when is_binary(name) and byte_size(name) > 320 ->
          Ash.Changeset.add_error(changeset, field: :display_name, message: "is too long")

        _ ->
          changeset
      end

    if Ash.Changeset.changing_attribute?(changeset, :wallet_address) do
      Ash.Changeset.before_action(changeset, fn locked ->
        RegentIdentity.lock(actor)
        wallet = Ash.Changeset.get_attribute(locked, :wallet_address)

        with {:ok, current} when not is_nil(current) <-
               RegentIdentity.get_my_profile(actor: actor),
             true <-
               is_nil(wallet) or
                 (wallet in actor.wallet_addresses and wallet in current.wallet_addresses) do
          locked
        else
          _ ->
            Ash.Changeset.add_error(locked,
              field: :wallet_address,
              message: "must be a verified linked wallet"
            )
        end
      end)
    else
      changeset
    end
  end

  def change(changeset, _, _),
    do: Ash.Changeset.add_error(changeset, "verified identity required")
end
