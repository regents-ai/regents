defmodule RegentsWeb.Keyfleet.PollJSON do
  @moduledoc "Polls and votes as the agent API and the polls pages' browser tools answer them."

  alias Regents.Keyfleet.Polls
  alias Regents.Keyfleet.Polls.Vote

  @doc """
  A poll as the fleet's members read it (`Regents.Keyfleet.Polls.Poll`): its
  question, choices, notes, how many votes it has drawn and, once closed,
  `totals`.
  """
  def poll(poll) do
    %{
      id: poll.id,
      question: poll.question,
      choices: poll.choices,
      started_by_key: poll.started_by_key,
      started_at: poll.inserted_at,
      closes_at: poll.closes_at,
      ended_at: poll.ended_at,
      open: Polls.open?(poll),
      votes_cast: poll.votes_cast,
      totals: poll.totals,
      notes: poll.notes
    }
  end

  @doc "A vote, as its Key's agents and the fleet's Key holders read it."
  def vote(vote), do: Vote.to_map(vote)
end
