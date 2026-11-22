defmodule Regents.Account.Agents.PairedPersonWallet do
  @moduledoc """
  The wallets of the person each agent is paired with, one row a wallet: the
  agent's wallet (`agent_wallet`), the person's account (`human_account_id`) and
  one of the person's wallets (`wallet`), every address lowercase. It reads the
  view `regents_app.paired_person_wallets`, which joins the pairing every Regent
  site shares (`regent_agents.paired_agents`) to this site's accounts on the
  sign-in id, so the sign-in id never leaves the Account area.

  The rows agree with `Regents.Account.Actors.Agent.with_pairing/1`: a pairing
  counts while its row exists (unpairing deletes it) and its person has an
  account here, and its wallets are the paired agent's `wallet_addresses`, the
  person's main and linked wallets that are addresses. A pairing whose person
  has no account here, or no wallet that is an address, has no rows. One agent
  wallet names one pairing and one pairing one account, so `agent_wallet` and
  `wallet` together name a row.

  Any product's resource may relate to it with explicit keys (its agent wallet
  against `agent_wallet`, or an account id or a wallet against the others) and
  filter, `exists` or calculate through it in SQL: Ash leaves this resource's
  policy out of a filter or calculation written in code. Its read, and with it a
  load or an aggregate through it, admits the system actor alone, since whom an
  agent acts for is for trusted code; an aggregate read for anyone else finds no
  rows. The one exception is `Regents.Keyfleet.Agents.AgentProfile`'s `paired_key`:
  two aggregates that skip this policy over its private `person_wallets`, since its
  `:here` filter needs the Key as an expression, and only a Key's number leaves.
  """

  use Ash.Resource,
    domain: Regents.Account.Agents,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "paired_person_wallets"
    repo(Regents.Repo)
    migrate?(false)
  end

  attributes do
    attribute :agent_wallet, :string, primary_key?: true, allow_nil?: false
    attribute :wallet, :string, primary_key?: true, allow_nil?: false
    attribute :human_account_id, :integer, allow_nil?: false
  end

  actions do
    defaults [:read]
  end

  policies do
    policy action_type(:read) do
      authorize_if Regents.Checks.SystemActor
    end
  end
end
