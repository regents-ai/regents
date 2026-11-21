defmodule Regents.Keyfleet.Polls.Changes.StartPoll do
  @moduledoc """
  Starts a poll as the starter's Key (`Regents.Keyfleet.Polls.voter/2`), open for the
  minutes asked, unless that Key started another in the last 24 hours
  (`PollLimitError`, with the seconds until it may start the next).

  A person and the agents taking part as their Key share the one Key's
  limit. Two starts for one Key at the same moment wait for each other, so
  only the first gets through.
  """
  use Ash.Resource.Change

  alias Regents.Account.Actors.System
  alias Regents.Keyfleet.Polls
  alias Regents.Keyfleet.Polls.Errors.PollLimitError
  alias Regents.Keyfleet.Rooms.Errors.NoKeyToWriteAsError

  @day 86_400

  @impl true
  def change(changeset, _opts, %{actor: actor}) do
    Ash.Changeset.before_action(changeset, &starter(&1, actor))
  end

  defp starter(changeset, actor) do
    fleet_id = Ash.Changeset.get_argument(changeset, :fleet_id)

    case Polls.voter(actor, fleet_id) do
      nil ->
        Ash.Changeset.add_error(changeset, NoKeyToWriteAsError.exception(fleet_id: fleet_id))

      %{key: key, wallet: wallet} ->
        lock!(fleet_id, key)

        case Polls.last_started!(fleet_id, key, actor: %System{}) do
          nil -> start(changeset, key, wallet)
          last -> Ash.Changeset.add_error(changeset, limit(last))
        end
    end
  end

  defp lock!(fleet_id, key) do
    Regents.Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
      Jason.encode!(["poll_start", fleet_id, key])
    ])
  end

  defp start(changeset, key, wallet) do
    minutes = Ash.Changeset.get_argument(changeset, :minutes)

    Ash.Changeset.force_change_attributes(changeset, %{
      started_by_key: key,
      started_by_wallet: wallet,
      closes_at: DateTime.add(DateTime.utc_now(), minutes, :minute)
    })
  end

  defp limit(%{inserted_at: started_at}) do
    seconds = DateTime.diff(DateTime.add(started_at, @day), DateTime.utc_now(), :second)
    PollLimitError.exception(retry_after: max(seconds, 1))
  end
end
