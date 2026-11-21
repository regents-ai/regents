defmodule Regents.Keyfleet.Proposals.Calculations.KeyBallots do
  @moduledoc """
  Each Key's vote on a proposal, as lists of token ids in order: `yes`, `no`
  and `abstain` hold the Keys whose latest vote, in chain order, is that
  choice, as `Regents.Keyfleet.Proposals.Calculations.LatestVotes` counts them; a Key
  may vote again and only its latest vote counts. `silent` holds the Keys
  present when the proposal opened that have not voted, which the contract
  counts against approval.

  A Key was present when it opened by the rule
  `Regents.Keyfleet.Proposals.Calculations.LateKeys` applies
  (`KeyfleetVotes.wasActiveAtOpening`): its last presence record before the
  proposal is a renewal or an automatic start at or before the opening and
  less than 48 hours before it. Ash takes a fragment's SQL only as written, so
  the two modules each spell the rule out, and a change to it changes both.
  """

  use Ash.Resource.Calculation

  import Ash.Expr

  # `KeyfleetPresence.WINDOW`.
  @window_seconds 172_800

  @impl true
  def expression(_opts, _context) do
    expr(
      fragment(
        """
        (SELECT jsonb_build_object(
          'yes', COALESCE(jsonb_agg(latest.token_id ORDER BY latest.token_id) FILTER (WHERE latest.choice = 'yes'), '[]'::jsonb),
          'no', COALESCE(jsonb_agg(latest.token_id ORDER BY latest.token_id) FILTER (WHERE latest.choice = 'no'), '[]'::jsonb),
          'abstain', COALESCE(jsonb_agg(latest.token_id ORDER BY latest.token_id) FILTER (WHERE latest.choice = 'abstain'), '[]'::jsonb),
          'silent', (
            SELECT COALESCE(jsonb_agg(candidate.token_id ORDER BY candidate.token_id), '[]'::jsonb)
            FROM (
              SELECT DISTINCT presence.token_id
              FROM keyfleet_app.key_presences AS presence
              WHERE presence.fleet_id = ?
            ) AS candidate
            WHERE NOT EXISTS (
              SELECT 1 FROM keyfleet_app.proposal_votes AS vote
              WHERE vote.proposal_id = ? AND candidate.token_id = ANY (vote.token_ids)
            )
            AND EXISTS (
              SELECT 1 FROM (
                SELECT presence.kind, presence.at
                FROM keyfleet_app.key_presences AS presence
                WHERE presence.fleet_id = ? AND presence.token_id = candidate.token_id
                  AND (presence.block_number, presence.log_index) < (?, ?)
                ORDER BY presence.block_number DESC, presence.log_index DESC
                LIMIT 1
              ) AS last
              WHERE last.kind IN ('present', 'scheduled') AND last.at <= ?
                AND ? < last.at + make_interval(secs => ?)
            )
          )
        ) FROM (
          SELECT DISTINCT ON (key.token_id) key.token_id, vote.choice
          FROM keyfleet_app.proposal_votes AS vote
          CROSS JOIN LATERAL unnest(vote.token_ids) AS key(token_id)
          WHERE vote.proposal_id = ?
          ORDER BY key.token_id, vote.block_number DESC, vote.log_index DESC
        ) AS latest)
        """,
        fleet_id,
        id,
        fleet_id,
        block_number,
        log_index,
        opened_at,
        opened_at,
        ^@window_seconds,
        id
      )
    )
  end
end
