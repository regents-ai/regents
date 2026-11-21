defmodule Regents.Keyfleet.Keys.Validations.HeldByPerson do
  @moduledoc """
  One of the signed-in person's wallets holds the Key the changeset names, in
  its fleet, right now. For an agent paired with a person here, the person's
  wallets.
  """
  use Ash.Resource.Validation

  alias Regents.Account.Actors.Agent
  alias Regents.Account.Actors.Human
  alias Regents.Keyfleet.Keys
  alias Regents.Keyfleet.Keys.Errors.KeyNotHeldError

  @impl true
  def validate(changeset, opts, %{actor: %Agent{pairing: %Human{} = person}} = context),
    do: validate(changeset, opts, %{context | actor: person})

  def validate(changeset, _opts, %{actor: %Human{wallet_addresses: wallets} = actor}) do
    fleet_id = Ash.Changeset.get_attribute(changeset, :fleet_id)
    token_id = Ash.Changeset.get_attribute(changeset, :token_id)

    case Keys.current_key(fleet_id, token_id, actor: actor) do
      {:ok, %{owner_wallet: owner}} when is_binary(owner) ->
        if owner in wallets, do: :ok, else: not_held(fleet_id, token_id)

      {:ok, nil} ->
        not_held(fleet_id, token_id)

      {:error, error} ->
        {:error, error}
    end
  end

  defp not_held(fleet_id, token_id),
    do: {:error, KeyNotHeldError.exception(fleet_id: fleet_id, token_id: token_id)}
end
