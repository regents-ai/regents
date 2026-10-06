defmodule Regents.Credits do
  @moduledoc """
  This site's part in Regent Credits (`RegentCredits`): the name it acts under
  and the actors it passes. The library keeps the balance; the site says who
  is asking, from what its own sign-in verified. Agent spending settings are
  saved only under this site's name.
  """

  alias RegentCredits.Actor

  @site "regents"
  @explorers %{base: "https://basescan.org/tx/", ethereum: "https://etherscan.io/tx/"}

  @doc "The name this site places holds and attaches wallets under."
  def site, do: @site

  @doc "The signed-in account, with the wallets its sign-in verified."
  def person(account), do: Actor.person(account.privy_user_id, account.wallet_addresses, @site)

  @doc "The site's own server code."
  def site_actor, do: Actor.site(@site)

  @doc "Where a person can see a transaction on its chain."
  def transaction_url(chain, tx_hash), do: @explorers[chain] <> tx_hash

  @doc "The sites a person may let an agent spend Credits on, with their names."
  def agent_sites, do: [{"patchbay", "patchbay.help"}]

  @doc "The signed-in account acting as a Credits admin; the library checks it is one."
  def admin(account), do: Actor.admin(account.privy_user_id)

  @doc "Whether the signed-in account is a Credits admin."
  def admin?(nil), do: false

  def admin?(account),
    do: account.privy_user_id in Application.fetch_env!(:regent_credits, :admins)
end
