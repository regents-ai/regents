defmodule Regents.Keyfleet.Dms.Changes.LimitSends do
  @moduledoc """
  Holds each sending Key to 300 direct messages an hour, counted from the
  messages it has stored in the last hour (`Regents.Keyfleet.Dms.Message`'s
  `:sent_last_hour`). A refused send stores nothing, so it never counts; a
  repeat of a message already sent is handed back, never refused. The count
  is the database's, so every machine sees the same one and a deploy keeps it.

  It runs after `Regents.Keyfleet.Dms.Changes.SendMessage` has taken the fleet's turn,
  so two sends from one Key are never counted at once. Opening a new
  conversation has no limit of its own.
  """
  use Ash.Resource.Change

  require Ash.Query

  alias Regents.Account.Actors.System
  alias Regents.Keyfleet.Dms.Errors.SendLimitError
  alias Regents.Keyfleet.Dms.Message

  @limit 300
  @hour 3_600

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn
      %{valid?: true} = changeset -> limit(changeset)
      changeset -> changeset
    end)
  end

  defp limit(changeset) do
    fleet_id = Ash.Changeset.get_attribute(changeset, :fleet_id)
    token_id = Ash.Changeset.get_attribute(changeset, :from_token_id)

    # The 300th newest message of the hour: while there is one, the Key is at
    # its limit until that message is an hour old.
    case Message
         |> Ash.Query.for_read(:sent_last_hour, %{fleet_id: fleet_id, token_id: token_id},
           actor: %System{}
         )
         |> Ash.Query.offset(@limit - 1)
         |> Ash.Query.limit(1)
         |> Ash.read!() do
      [] ->
        changeset

      [oldest] ->
        if sent?(changeset),
          do: changeset,
          else: Ash.Changeset.add_error(changeset, refusal(oldest))
    end
  end

  defp sent?(changeset) do
    fleet_id = Ash.Changeset.get_attribute(changeset, :fleet_id)
    token_id = Ash.Changeset.get_attribute(changeset, :from_token_id)
    epoch = Ash.Changeset.get_attribute(changeset, :from_ownership_epoch)
    key = Ash.Changeset.get_attribute(changeset, :idempotency_key)

    Message
    |> Ash.Query.for_read(:read, %{}, actor: %System{})
    |> Ash.Query.filter(
      fleet_id == ^fleet_id and from_token_id == ^token_id and from_ownership_epoch == ^epoch and
        idempotency_key == ^key
    )
    |> Ash.exists?()
  end

  defp refusal(%Message{inserted_at: oldest}) do
    seconds = DateTime.diff(DateTime.add(oldest, @hour), DateTime.utc_now(), :second)
    SendLimitError.exception(limit: @limit, retry_after: max(seconds, 1))
  end
end
