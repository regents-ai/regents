defmodule Regents.Repo.Migrations.AddAccountViews do
  @moduledoc """
  Two read-only views the Account area owns, so a product's query can join what
  Account knows without naming its tables or the sign-in id.

  `regents_app.paired_person_wallets` (`Regents.Account.Agents.PairedPersonWallet`):
  for each agent paired with a person who has an account here, one row for each
  of the person's wallets that is an address. `agent_wallet` is the pairing's
  wallet as stored, which the one writer of pairings keeps lowercase
  (`RegentAgents.PairedAgent`) and which an agent's pairing is looked up by
  (`RegentAgents.Authority.resolve/2`); `wallet` is lowercased here.

  `regents_app.public_links` (`Regents.Account.Accounts.PublicLink`): the
  verified social links that name a username, with the account, provider,
  username and display name alone.

  Hand-written: views are not Ash resources' tables. Creates the two views and
  nothing else; no table, row or right changes. `down` drops them.
  """

  use Ecto.Migration

  def up do
    execute("""
    CREATE VIEW regents_app.paired_person_wallets AS
    SELECT pairing.wallet AS agent_wallet,
           account.id AS human_account_id,
           person.wallet
    FROM regent_agents.paired_agents AS pairing
    JOIN regent_names.platform_human_users AS account
      ON account.privy_user_id = pairing.privy_user_id
    CROSS JOIN LATERAL (
      SELECT DISTINCT lower(linked.wallet) AS wallet
      FROM unnest(array_prepend(account.wallet_address, account.wallet_addresses))
        AS linked(wallet)
      WHERE lower(linked.wallet) ~ '^0x[0-9a-f]{40}$'
    ) AS person
    """)

    execute("""
    CREATE VIEW regents_app.public_links AS
    SELECT human_account_id, provider, username, display_name
    FROM regents_app.linked_identities
    WHERE username IS NOT NULL
    """)
  end

  def down do
    execute("DROP VIEW regents_app.public_links")
    execute("DROP VIEW regents_app.paired_person_wallets")
  end
end
