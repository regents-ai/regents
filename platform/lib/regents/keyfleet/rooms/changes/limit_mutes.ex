defmodule Regents.Keyfleet.Rooms.Changes.LimitMutes do
  @moduledoc """
  Keeps each muter to 500 mutes across the fleets, since every room page and
  agent sync reads all of a muter's mutes in its fleet. Muting a key already
  muted keeps the one mute, so it is never refused.

  The count is taken while the muter's mutes are held for this one alone
  until it commits, so two mutes at the same moment can't both take the last.
  """
  use Ash.Resource.Change

  require Ash.Query

  alias Regents.Keyfleet.Rooms.Errors.MuteLimitError
  alias Regents.Keyfleet.Rooms.Mute

  @limit 500

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn
      %{valid?: true} = changeset ->
        limit(changeset, Ash.Changeset.get_attribute(changeset, :muter))

      changeset ->
        changeset
    end)
  end

  # With nobody signed in there is no muter, and the mute is refused anyway.
  defp limit(changeset, nil), do: changeset

  defp limit(changeset, muter) do
    Regents.Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
      Jason.encode!(["mutes", muter])
    ])

    if count(muter) < @limit or muted?(changeset, muter),
      do: changeset,
      else: Ash.Changeset.add_error(changeset, MuteLimitError.exception(limit: @limit))
  end

  defp count(muter) do
    # The limit counts the muter's mutes in every fleet, not only this one's.
    Mute |> Ash.Query.filter(muter == ^muter) |> Ash.count!(authorize?: false)
  end

  defp muted?(changeset, muter) do
    fleet_id = Ash.Changeset.get_attribute(changeset, :fleet_id)
    token_id = Ash.Changeset.get_attribute(changeset, :token_id)

    Mute
    |> Ash.Query.filter(muter == ^muter and fleet_id == ^fleet_id and token_id == ^token_id)
    # A repeat mute is checked against the muter's own row, whoever may read it.
    |> Ash.exists?(authorize?: false)
  end
end
