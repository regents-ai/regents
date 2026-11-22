defmodule Regents.Keyfleet.Agents.Changes.TrackProfileActivity do
  @moduledoc false
  use Ash.Resource.Change

  @impl true
  def change(changeset, opts, context) do
    case atomic(changeset, opts, context) do
      {:atomic, updates} -> Ash.Changeset.atomic_update(changeset, updates)
      {:error, error} -> Ash.Changeset.add_error(changeset, error)
    end
  end

  @impl true
  def atomic(changeset, _opts, _context) do
    status_submitted? =
      Map.has_key?(changeset.params, :current_status) or
        Map.has_key?(changeset.params, "current_status")

    if Enum.any?(changeset.action.accept, fn field ->
         Map.has_key?(changeset.params, field) or Map.has_key?(changeset.params, to_string(field))
       end) do
      {:atomic,
       %{
         last_activity_at: expr(fragment("clock_timestamp() AT TIME ZONE 'utc'")),
         status_updated_at:
           expr(
             if ^status_submitted?,
               do: fragment("clock_timestamp() AT TIME ZONE 'utc'"),
               else: status_updated_at
           )
       }}
    else
      {:error,
       Ash.Error.Changes.InvalidChanges.exception(message: "Supply at least one profile field")}
    end
  end
end
