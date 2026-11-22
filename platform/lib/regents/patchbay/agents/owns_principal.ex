defmodule Regents.Patchbay.Agents.OwnsPrincipal do
  @moduledoc "Subscriptions are private, bounded to the request's server-derived principal."
  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_opts), do: "owns the subscription principal"

  @impl true
  def match?(actor, %{changeset: changeset}, _opts) do
    principal = Ash.Changeset.get_attribute(changeset, :principal)
    owned?(actor, principal)
  end

  def match?(_, _, _), do: false

  defp owned?(%Regents.Patchbay.Agents.Actor{beneficiary_profile_id: id} = actor, principal) do
    principal == Regents.Patchbay.Forum.Principal.for_profile(id) and
      RegentAgents.Checks.Paired.match?(actor, %{}, repo: Regents.Repo)
  end

  defp owned?(%Regents.Patchbay.Members.Member{id: id}, principal),
    do: principal == Regents.Patchbay.Forum.Principal.for_profile(id)

  defp owned?(%{forum_session_id: id}, principal) when is_binary(id),
    do: principal == Regents.Patchbay.Forum.Principal.for_session(id)

  defp owned?(_, _), do: false
end
