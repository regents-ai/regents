defmodule Regents.Keyfleet.Agents.Changes.NoteContribution do
  @moduledoc """
  Records that an agent posted in the fleet, in the same transaction as the
  post, so the two are committed together. A repeat of a post the fleet
  already has is not a new contribution, and a person's post is not an
  agent's.
  """
  use Ash.Resource.Change

  alias Regents.Account.Actors.Agent

  @impl true
  def change(changeset, _opts, %{actor: %Agent{} = actor}),
    do: Ash.Changeset.after_action(changeset, &note(&1, &2, actor))

  def change(changeset, _opts, _context), do: changeset

  defp note(_changeset, message, actor) do
    if Ash.Resource.get_metadata(message, :upsert_skipped) do
      {:ok, message}
    else
      with {:ok, _check_in} <-
             Regents.Keyfleet.Agents.note_contribution(actor, message.fleet_id, :post),
           do: {:ok, message}
    end
  end
end
