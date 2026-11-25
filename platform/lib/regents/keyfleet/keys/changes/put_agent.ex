defmodule Regents.Keyfleet.Keys.Changes.PutAgent do
  @moduledoc """
  Puts the agent the person's write names by its wallet on the Key, inside
  the write's own transaction once the policy has let it through
  (`Regents.Keyfleet.Keys.AgentKey`, the person's alone). The agent's row in the
  fleet is overwritten, so it comes off the Key it was on there.

  First the named agent's current pairing with the person is locked
  (`RegentAgents.Authority.lock_current/3`), whose id is what is kept: only
  an agent paired with the account goes on its Keys, and a wallet no agent
  paired with the person has now is `AgentUnknownError`. Every write about an
  agent locks its pairing, so two at once run one after the other. Then the
  agent's row in the fleet is locked, and the Key it names and the Key it is
  on now are read as the chain records them: the person's wallets must hold
  the Key (`KeyNotHeldError` otherwise), and the row is saved with the Key's
  ownership record as it is then. A row whose Key has changed hands since it
  was saved puts the agent on no Key (`Regents.Keyfleet.Keys.placed_on?/3`).

  The Key the agent left goes in the change's context (`:left_token_id`), for
  `Regents.Keyfleet.Keys.Changes.TellKeysChanged`.
  """
  use Ash.Resource.Change

  require Ash.Query

  alias Regents.Account.Actors.Agent
  alias Regents.Keyfleet.Keys
  alias Regents.Keyfleet.Keys.AgentKey
  alias Regents.Keyfleet.Keys.Errors.{AgentUnknownError, KeyNotHeldError}

  @impl true
  def change(changeset, _opts, %{actor: actor}),
    do: Ash.Changeset.before_action(changeset, &put(&1, actor))

  defp put(changeset, actor) do
    wallet = changeset |> Ash.Changeset.get_argument(:agent_wallet) |> String.downcase()
    fleet_id = Ash.Changeset.get_attribute(changeset, :fleet_id)
    token_id = Ash.Changeset.get_attribute(changeset, :token_id)

    with {:ok, %{id: pairing_id}} <- lock_pairing(actor, wallet),
         {:ok, row} <- lock_row(fleet_id, pairing_id, actor),
         {:ok, key, standing} <- read_keys(fleet_id, token_id, row, actor) do
      changeset
      |> Ash.Changeset.force_change_attribute(:paired_agent_id, pairing_id)
      |> Ash.Changeset.force_change_attribute(:ownership_epoch, key.ownership_epoch)
      |> Ash.Changeset.set_context(%{left_token_id: standing && standing.token_id})
    else
      {:error, error} -> Ash.Changeset.add_error(changeset, error)
    end
  end

  # The named agent's current pairing with the person.
  defp lock_pairing(actor, wallet) do
    with {:ok, person} <- Keys.person_privy_id(actor),
         {:ok, pairing} <- Agent.lock_current_pairing(person, wallet) do
      {:ok, pairing}
    else
      not_theirs when not_theirs in [:error, {:error, :not_paired}] ->
        {:error, AgentUnknownError.exception(wallet: wallet)}

      {:error, error} ->
        {:error, error}
    end
  end

  # The named agent's row in the fleet, if it has one.
  defp lock_row(fleet_id, pairing_id, actor) do
    AgentKey
    |> Ash.Query.filter(fleet_id == ^fleet_id and paired_agent_id == ^pairing_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(actor: actor)
  end

  # The Key's ownership record now, whose epoch the write keeps, and the
  # agent's row if it still stands on its Key. The person's wallets hold the
  # Key; one the record no longer shows is not held.
  defp read_keys(fleet_id, token_id, row, actor) do
    wallets = Keys.person_wallets(actor)
    token_ids = Enum.uniq([token_id | List.wrap(row && row.token_id)])
    query = Ash.Query.filter(Regents.Keyfleet.Keys.KeyAttachment, token_id in ^token_ids)

    with {:ok, keys} <- Keys.keys_held_in_fleet(fleet_id, wallets, actor: actor, query: query) do
      keys = Map.new(keys, &{&1.token_id, &1})

      case keys[token_id] do
        nil -> {:error, KeyNotHeldError.exception(fleet_id: fleet_id, token_id: token_id)}
        key -> {:ok, key, standing(row, keys, wallets)}
      end
    end
  end

  defp standing(nil, _keys, _wallets), do: nil

  defp standing(row, keys, wallets),
    do: if(Keys.placed_on?(row, keys[row.token_id], wallets), do: row)
end
