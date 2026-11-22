defmodule Regents.Keyfleet.Rooms.Changes.LimitPosts do
  @moduledoc """
  Holds each key to 300 posts an hour that people write themselves, and each
  agent to 300 an hour as each key it writes as, across the fleet's rooms and
  keys' threads.

  People post from the page and its tools, which the API's per-address limit
  doesn't reach. Their posts are counted from the ones stored in the last
  hour (`Regents.Keyfleet.Rooms.Message`'s `:page_posts_last_hour`), so a deploy keeps
  the count. It runs after `Regents.Keyfleet.Rooms.Changes.PostMessage` has settled
  the key the post is written as, and holds that key's posts for this one
  alone until it commits, so two posts as one key at the same moment, in two
  rooms or threads, are counted one after the other.

  Agents post through the API, but an agent changing its address would start
  that limit again, so each agent wallet also spends the `:keyfleet_agent_posts`
  allowance of the key it writes as: its own posts and the ones it writes for
  its person alike. Each wallet has its own, so one shard holder's agent
  never uses up another's.

  A refused post stores nothing; a repeat of a post already made is handed
  back, never refused.
  """
  use Ash.Resource.Change

  alias Regents.Account.Actors.System
  alias Regents.Keyfleet.Rooms
  alias Regents.Keyfleet.Rooms.Errors.PostLimitError
  alias Regents.Keyfleet.Rooms.Message
  alias Regents.Limits

  @limit 300
  @hour 3_600

  @impl true
  def change(changeset, _opts, %{actor: actor}) do
    Ash.Changeset.before_action(changeset, fn
      %{valid?: true} = changeset -> limit(changeset, actor)
      changeset -> changeset
    end)
  end

  defp limit(changeset, actor) do
    if persons_own?(changeset),
      do: limit_person(changeset, actor),
      else: limit_agent(changeset, actor)
  end

  defp persons_own?(changeset),
    do:
      Ash.Changeset.get_attribute(changeset, :author_kind) == :human and
        is_nil(Ash.Changeset.get_attribute(changeset, :via_agent_profile_id))

  defp limit_person(changeset, actor) do
    fleet_id = Ash.Changeset.get_attribute(changeset, :fleet_id)
    token_id = Ash.Changeset.get_attribute(changeset, :as_key)

    Regents.Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
      Jason.encode!(["page_posts", fleet_id, token_id])
    ])

    # The 300th newest post of the hour: while there is one, the key is at its
    # limit until that post is an hour old.
    case Message
         |> Ash.Query.for_read(
           :page_posts_last_hour,
           %{fleet_id: fleet_id, token_id: token_id},
           actor: %System{}
         )
         |> Ash.Query.offset(@limit - 1)
         |> Ash.Query.limit(1)
         |> Ash.read!() do
      [] ->
        changeset

      [%Message{inserted_at: oldest}] ->
        seconds = DateTime.diff(DateTime.add(oldest, @hour), DateTime.utc_now(), :second)
        refuse(changeset, actor, max(seconds, 1))
    end
  end

  defp limit_agent(changeset, actor) do
    who = {
      Ash.Changeset.get_attribute(changeset, :fleet_id),
      Ash.Changeset.get_attribute(changeset, :as_key),
      Ash.Changeset.get_attribute(changeset, :author_wallet)
    }

    case Limits.admit(:keyfleet_agent_posts, who) do
      :ok -> changeset
      {:limited, seconds} -> refuse(changeset, actor, seconds)
    end
  end

  defp refuse(changeset, actor, retry_after) do
    if repeat?(changeset, actor),
      do: changeset,
      else:
        Ash.Changeset.add_error(
          changeset,
          PostLimitError.exception(limit: @limit, retry_after: retry_after)
        )
  end

  # Looked for as the one posting, who may read their own posts on every
  # key's thread.
  defp repeat?(changeset, actor) do
    Rooms.get_post_under_send_key!(
      Ash.Changeset.get_attribute(changeset, :fleet_id),
      [Ash.Changeset.get_attribute(changeset, :author_wallet)],
      Ash.Changeset.get_attribute(changeset, :idempotency_key),
      actor: actor
    ) != nil
  end
end
