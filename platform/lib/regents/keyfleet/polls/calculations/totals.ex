defmodule Regents.Keyfleet.Polls.Calculations.Totals do
  @moduledoc """
  A closed poll's result as the fleet's members read it: each choice's count of votes, in
  the order the choices were listed, without who voted. Nil while the poll is
  open, so no one sees which way it leans before it closes.
  """
  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context), do: [:choices, :vote_choices, :closes_at, :ended_at]

  @impl true
  def calculate(polls, _opts, _context) do
    now = DateTime.utc_now()
    Enum.map(polls, &if(Regents.Keyfleet.Polls.open?(&1, now), do: nil, else: totals(&1)))
  end

  defp totals(poll) do
    counts = Enum.frequencies(poll.vote_choices)
    Enum.map(poll.choices, &%{choice: &1, votes: Map.get(counts, &1, 0)})
  end
end
