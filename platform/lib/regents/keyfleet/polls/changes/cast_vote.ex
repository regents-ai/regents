defmodule Regents.Keyfleet.Polls.Changes.CastVote do
  @moduledoc """
  Records a Key's vote, or hands back the vote that Key already has.

  A first vote needs the poll still open and one of its choices. The poll is
  read under a shared lock, so a poll being ended at that moment either takes
  this vote or turns it away, never both.
  """
  use Ash.Resource.Change

  require Ash.Query

  alias Regents.Keyfleet.Polls
  alias Regents.Keyfleet.Polls.Errors.ChoiceUnknownError
  alias Regents.Keyfleet.Polls.Errors.PollClosedError
  alias Regents.Keyfleet.Polls.Errors.PollUnknownError
  alias Regents.Keyfleet.Polls.Errors.VoteConflictError
  alias Regents.Keyfleet.Polls.Poll
  alias Regents.Keyfleet.Rooms.Errors.NoKeyToWriteAsError

  @impl true
  def change(changeset, _opts, %{actor: actor}) do
    changeset
    |> Ash.Changeset.before_action(&place(&1, actor))
    |> Ash.Changeset.after_action(&same_choice/2)
  end

  defp place(changeset, actor) do
    fleet_id = Ash.Changeset.get_argument(changeset, :fleet_id)
    poll_id = Ash.Changeset.get_argument(changeset, :poll_id)

    with {:ok, poll} <- poll(fleet_id, poll_id),
         {:ok, %{key: key, wallet: wallet}} <- voter(actor, fleet_id),
         :ok <- open(poll, key, changeset) do
      Ash.Changeset.force_change_attributes(changeset, %{
        poll_id: poll.id,
        token_id: key,
        wallet: wallet
      })
    else
      {:error, error} -> Ash.Changeset.add_error(changeset, error)
    end
  end

  # The vote itself was authorized, by the standing that reads the poll.
  defp poll(fleet_id, poll_id) do
    Poll
    |> Ash.Query.filter(id == ^poll_id and fleet_id == ^fleet_id)
    |> Ash.Query.lock("FOR SHARE")
    |> Ash.read_one!(authorize?: false)
    |> case do
      nil -> {:error, PollUnknownError.exception(poll_id: poll_id)}
      poll -> {:ok, poll}
    end
  end

  defp voter(actor, fleet_id) do
    case Polls.voter(actor, fleet_id) do
      nil -> {:error, NoKeyToWriteAsError.exception(fleet_id: fleet_id)}
      voter -> {:ok, voter}
    end
  end

  # A Key that already voted is answered with its vote, whatever has happened
  # to the poll since, so a voter that never heard the answer can ask again.
  defp open(poll, key, changeset) do
    choice = Ash.Changeset.get_attribute(changeset, :choice)

    cond do
      voted?(poll, key) -> :ok
      not Polls.open?(poll) -> {:error, PollClosedError.exception([])}
      choice not in poll.choices -> {:error, ChoiceUnknownError.exception(choice: choice)}
      true -> :ok
    end
  end

  # Read past the votes' own policies: whether the Key already voted decides
  # this vote's answer, and the vote itself was authorized.
  defp voted?(poll, key),
    do:
      Regents.Keyfleet.Polls.Vote
      |> Ash.Query.filter(poll_id == ^poll.id and token_id == ^key)
      |> Ash.exists?(authorize?: false)

  defp same_choice(changeset, vote) do
    cond do
      Ash.Resource.get_metadata(vote, :upsert_skipped) != true -> {:ok, vote}
      vote.choice == Ash.Changeset.get_attribute(changeset, :choice) -> {:ok, vote}
      true -> {:error, VoteConflictError.exception([])}
    end
  end
end
