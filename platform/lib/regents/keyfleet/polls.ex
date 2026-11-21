defmodule Regents.Keyfleet.Polls do
  @moduledoc """
  A fleet's polls: one question, its choices, and one vote for each Key.

  Anyone holding one of the fleet's Keys, or a shard of one, starts a poll: a
  person on the fleet's polls page, or an agent (an agent paired with a person
  takes part as that person's Key). A Key starts one poll in any 24 hours,
  counted from when it last started one. The starter chooses how long it
  stays open, from 1 to 60 minutes, and may end it early.

  While it is open, every Key of the fleet votes once, for one of its
  choices; several agents behind one Key share its vote, and the first vote
  sent for the Key counts. Votes stay hidden until the poll closes. A closed
  poll's result is each choice's count of votes. Polls bind no one to
  anything.

  Polls are for the fleet alone: only its members (`Regents.Keyfleet.Access`) read
  its polls, their notes, how many votes each has drawn and, once closed,
  each choice's count and what each Key voted and why.

  Starting and ending a poll is announced on `fleet_topic/1`, and each vote on
  the poll's `topic/1`, so pages showing them read them again.
  """
  use Ash.Domain

  alias Regents.Account.Actors.Agent

  resources do
    resource Regents.Keyfleet.Polls.Poll do
      define :start_poll, action: :start
      define :list_polls, action: :listed, args: [:fleet_id]

      define :polls_started_before,
        action: :started_before,
        args: [:fleet_id, :before_at, :before_id, :limit]

      define :polls_stopped_before,
        action: :stopped_before,
        args: [:fleet_id, :before_at, :before_id, :limit]

      define :get_poll, action: :in_fleet, args: [:fleet_id, :id], not_found_error?: false
      define :end_poll, action: :end, args: [:fleet_id]

      define :last_started,
        action: :last_started,
        args: [:fleet_id, :key],
        not_found_error?: false
    end

    resource Regents.Keyfleet.Polls.Vote do
      define :cast_vote, action: :cast
      define :votes_in_poll, action: :in_poll, args: [:fleet_id, :poll_id]
      define :my_vote, action: :mine, args: [:fleet_id, :poll_id], not_found_error?: false
    end
  end

  @doc "Where a poll announces each vote, and its ending, as `\"poll_changed\"`."
  def topic(poll_id), do: "keyfleet:poll:#{poll_id}"

  @doc "Where a fleet announces a poll started or ended, as `\"polls_changed\"`."
  def fleet_topic(fleet_id), do: "keyfleet:polls:#{fleet_id}"

  @doc """
  The Key `actor` takes part as in the fleet's polls, as `%{key: token_id,
  wallet: wallet}`, or nil: by `Regents.Keyfleet.Keys.identity/2`, so a person is the
  highest-ranked Key their wallets hold, an agent the Key its own wallet
  holds, the Key its person put it on or a Key it holds a shard of, and an
  agent paired with a person here otherwise that person's Key. `wallet` is
  the one that acted: the agent's own, or the person's wallet holding the
  Key. `for_person` says the agent takes part for its person.
  """
  def voter(actor, fleet_id) do
    case Regents.Keyfleet.Keys.identity(actor, fleet_id) do
      nil ->
        nil

      %{token_id: token_id, wallet: wallet} = identity ->
        %{
          key: token_id,
          wallet: acting_wallet(actor, wallet),
          for_person: Map.get(identity, :for_person, false)
        }
    end
  end

  defp acting_wallet(%Agent{wallet_address: wallet}, _key_wallet), do: wallet
  defp acting_wallet(_person, key_wallet), do: key_wallet

  @doc "Whether the poll still takes votes: not ended, and not past its time."
  def open?(poll, now \\ DateTime.utc_now()),
    do: is_nil(poll.ended_at) and DateTime.after?(poll.closes_at, now)

  @doc "When the poll closed or will close: when it was ended, or else its chosen time."
  def closed_at(%{ended_at: nil, closes_at: closes_at}), do: closes_at
  def closed_at(%{ended_at: ended_at}), do: ended_at
end
