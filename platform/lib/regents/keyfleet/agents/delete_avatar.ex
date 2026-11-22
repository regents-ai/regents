defmodule Regents.Keyfleet.Agents.DeleteAvatar do
  @moduledoc """
  Deletes a picture an agent replaced or removed from the bucket. Queued in
  the same transaction as the profile change (`Regents.Keyfleet.Agents.Changes.ReplaceAvatar`),
  so a change rolled back deletes nothing. A key is never set again once
  replaced, and deleting one already gone succeeds, so running twice is safe.
  """
  use Oban.Worker,
    queue: :keyfleet_avatars,
    max_attempts: 20,
    unique: [keys: [:key], period: :infinity, states: :incomplete]

  alias Regents.Keyfleet.Agents.AvatarBucket

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"key" => key}}), do: AvatarBucket.delete(key)
end
