defmodule Regents.Keyfleet.Proposals.Calculations.LatestVotes do
  @moduledoc """
  How many of a proposal's keys last voted `choice`: a key may vote again,
  and only its latest vote, in chain order, counts.
  """

  use Ash.Resource.Calculation

  import Ash.Expr

  @impl true
  def init(opts), do: {:ok, Keyword.take(opts, [:choice])}

  @impl true
  def expression(opts, _context) do
    choice = opts |> Keyword.fetch!(:choice) |> Atom.to_string()

    expr(
      fragment(
        """
        (SELECT count(*) FROM (
          SELECT DISTINCT ON (key.token_id) vote.choice
          FROM keyfleet_app.proposal_votes AS vote
          CROSS JOIN LATERAL unnest(vote.token_ids) AS key(token_id)
          WHERE vote.proposal_id = ?
          ORDER BY key.token_id, vote.block_number DESC, vote.log_index DESC
        ) AS latest WHERE latest.choice = ?)
        """,
        id,
        ^choice
      )
    )
  end
end
