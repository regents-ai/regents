defmodule RegentsWeb.Keyfleet.Standing do
  @moduledoc """
  An agent's standing in one fleet, as the fleet check
  (`RegentsWeb.Keyfleet.AgentDoctorController`) and a write's preview
  (`RegentsWeb.Keyfleet.Preview`) tell it: its profile, the Key it acts as and
  whether its person put it on that Key, the Keys it may act as, whether the
  fleet's key ownership is fresh, and each thing missing as the refusal an
  operation would answer. Nothing is written.
  """

  alias Regents.Keyfleet.{Agents, Chain, Keys}
  alias RegentsWeb.Keyfleet.Refusal

  @doc "`{:ok, standing}`, or `{:error, error}` when the profile can't be read."
  def read(actor, fleet_id) do
    with {:ok, profile} <- Agents.get_my_profile(actor: actor) do
      key = key(actor, fleet_id)
      fresh = Chain.fresh?(fleet_id)

      {:ok,
       %{
         profile: profile,
         key: key,
         keys: Keys.held_keys(actor, fleet_id),
         fresh: fresh,
         missing: missing(actor, profile, fresh, key)
       }}
    end
  end

  # The Key the agent acts as here, as every write names it, whether its
  # person put it on that Key (`Regents.Keyfleet.Keys.AgentKey`), and whether a vote
  # of the fleet has stopped it changing the workspace.
  defp key(actor, fleet_id) do
    with %{token_id: token_id} = identity <- Keys.identity(actor, fleet_id) do
      {:ok, restricted} = Keys.edits_restricted?(fleet_id, token_id)
      for_person = Map.get(identity, :for_person, false)

      %{
        token_id: token_id,
        for_person: for_person,
        assigned: for_person and assigned?(actor, fleet_id, token_id),
        edits_restricted: restricted
      }
    end
  end

  defp assigned?(actor, fleet_id, token_id),
    do: match?({:ok, %{token_id: ^token_id}}, Keys.assigned_key(actor, fleet_id))

  # Each thing between the agent and the fleet's work, in the order to fix
  # them, as the refusal an operation would answer.
  defp missing(actor, profile, fresh, key) do
    [
      actor.pairing == :person_not_here && "person_not_here",
      profile == nil && "profile_not_found",
      not fresh && "ownership_refreshing",
      (fresh and key == nil) && "not_a_member",
      match?(%{edits_restricted: true}, key) && "edits_restricted"
    ]
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&Refusal.body(&1).error)
  end
end
