defmodule Regents.Keyfleet.Agents.Calculations.PairedKey do
  @moduledoc """
  The key the person this agent is paired with writes as
  (`RegentAgents.PairedAgent`): the one they chose on the Account page while
  any of their wallets holds it (`Regents.Keyfleet.Keys.PostingKey`), else the
  lowest-numbered of the fleets' keys their wallets hold now. The person's
  wallets are for trusted code only (their read admits the system actor
  alone), so they are reached here through `person_wallets` without that
  read, by the agent's own wallet alone, and only the key's number leaves.
  Each wallet's keys are read in SQL, as `held_key`'s are, and each wallet
  is looked up on its own: matched as a set, every key in the fleet was
  read for every agent, 7 seconds for a full Regents Club.

  The read-only venue's database login is not granted the person's wallets
  (`regents_app.paired_person_wallets`), so there the expression names none
  of them and no agent has a paired Key: an agent is here, and acts as a Key,
  only by its own wallet, a Key its person put it on or its shard. The venue
  is set as the site starts (`Regents.read_only?/0`), so a running site builds
  the same expression for every query. This is the one place the agents here
  are read through the person's wallets.
  """
  use Ash.Resource.Calculation

  @impl true
  def expression(_opts, _context), do: paired_key(Regents.read_only?())

  defp paired_key(true), do: expr(nil)

  # The person's wallets admit the system actor alone, so both reads of them
  # here skip that check: they are matched by the agent's own wallet, and only
  # the key's number leaves.
  defp paired_key(false),
    do:
      expr(
        min(person_wallets,
          expr:
            fragment(
              """
              (SELECT min(held.token_id)
               FROM keyfleet_app.key_attachments AS held
               JOIN keyfleet_app.posting_keys AS chosen
                 ON chosen.fleet_id = held.fleet_id AND chosen.token_id = held.token_id
               WHERE held.owner_wallet = ? AND chosen.human_account_id = ?
                 AND held.fleet_id = ANY(?)
                 AND held.ownership_epoch = (
                   SELECT max(epoch.ownership_epoch)
                   FROM keyfleet_app.key_attachments AS epoch
                   WHERE epoch.fleet_id = held.fleet_id AND epoch.token_id = held.token_id
                 ))
              """,
              wallet,
              human_account_id,
              ^arg(:fleet_ids)
            ),
          expr_type: :integer,
          authorize?: false
        ) ||
          min(person_wallets,
            expr:
              fragment(
                """
                (SELECT min(held.token_id)
                 FROM keyfleet_app.key_attachments AS held
                 WHERE held.owner_wallet = ? AND held.fleet_id = ANY(?)
                   AND held.ownership_epoch = (
                     SELECT max(epoch.ownership_epoch)
                     FROM keyfleet_app.key_attachments AS epoch
                     WHERE epoch.fleet_id = held.fleet_id AND epoch.token_id = held.token_id
                   ))
                """,
                wallet,
                ^arg(:fleet_ids)
              ),
            expr_type: :integer,
            authorize?: false
          )
      )
end
