defmodule AshPlatformWeb.AccountLive do
  @moduledoc """
  The signed-in person's own page: who the site knows them as, the wallets
  their sign-in verified, the names those wallets hold and the accounts they
  have connected.

  Everything here is read from the sign-in the shell already holds; nothing on
  the page asks the visitor to sign in again.
  """

  use AshPlatformWeb, :html

  import AshPlatformWeb.Components.VerifiedConnections

  alias AshPlatform.PublicIdentity

  attr :account, :map, default: nil
  attr :account_control, :map, required: true
  attr :names, :any, default: nil
  attr :verified_connections, :list, default: []
  attr :verified_connections_notice, :map, default: nil

  def page(assigns) do
    ~H"""
    <article id="account-page" class="account-page">
      <header class="account-heading">
        <p class="account-kicker">Regents Labs</p>
        <h1 tabindex="-1">Account</h1>
        <p class="account-lede">
          The wallet you signed in with, the names it holds and the accounts you have connected.
        </p>
      </header>

      <section :if={is_nil(@account)} class="account-panel account-signed-out">
        <h2>Sign in to see your account</h2>
        <p>Your wallet, names and connections appear here once you are signed in.</p>
        <Regent.Primitives.button type="button" data-account-target="sign-in">
          Sign in
        </Regent.Primitives.button>
      </section>

      <div :if={@account} class="account-grid">
        <Regent.HolographicCard.card
          id="account-identity"
          class="account-identity"
          phx-hook="HolographicCard"
        >
          <p class="account-kicker">Regents account</p>
          <div class="account-identity__who">
            <img
              :if={@account_control.avatar_src}
              class="account-identity__avatar"
              src={@account_control.avatar_src}
              referrerpolicy="no-referrer"
              width="64"
              height="64"
              alt=""
            />
            <div class="account-identity__name">
              <h2>{@account_control.label}</h2>
              <p :if={short_wallet(@account) not in [nil, @account_control.label]}>
                <code>{short_wallet(@account)}</code>
              </p>
            </div>
          </div>
        </Regent.HolographicCard.card>

        <section class="account-panel account-details" aria-labelledby="account-details-title">
          <h2 id="account-details-title">Details</h2>
          <dl>
            <div>
              <dt>Wallet</dt>
              <dd :if={@account.wallet_address} class="account-wallet">
                <code>{@account.wallet_address}</code>
                <Regent.Primitives.button
                  id="account-wallet-copy"
                  type="button"
                  variant="secondary"
                  phx-hook="CopyText"
                  data-copy-text={@account.wallet_address}
                >
                  Copy
                </Regent.Primitives.button>
              </dd>
              <dd :if={is_nil(@account.wallet_address)}>No wallet linked</dd>
            </div>
            <div :if={other_wallets(@account) != []}>
              <dt>Other linked wallets</dt>
              <dd>
                <ul class="account-wallet-list">
                  <li :for={wallet <- other_wallets(@account)}><code>{wallet}</code></li>
                </ul>
              </dd>
            </div>
            <div>
              <dt>ENS name</dt>
              <dd>{@account.ens_name || "None found for this wallet"}</dd>
            </div>
            <div>
              <dt>Display name</dt>
              <dd>{@account.display_name || "Not set"}</dd>
            </div>
            <div>
              <dt>World ID</dt>
              <dd :if={@account.world_verified_at}>
                Verified on {date(@account.world_verified_at)}
              </dd>
              <dd :if={is_nil(@account.world_verified_at)}>Not verified</dd>
            </div>
          </dl>
        </section>

        <section class="account-panel account-names" aria-labelledby="account-names-title">
          <h2 id="account-names-title">Historical names</h2>
          <.names names={@names} />
        </section>

        <.verified_connections
          id="account-verified-connections"
          class="account-panel"
          identities={@verified_connections}
          notice={@verified_connections_notice}
        />

        <section class="account-panel account-session" aria-labelledby="account-session-title">
          <h2 id="account-session-title">Session</h2>
          <p>Signing out ends this session on this browser only.</p>
          <Regent.Primitives.button type="button" variant="secondary" data-account-target="sign-out">
            Sign out
          </Regent.Primitives.button>
        </section>
      </div>
    </article>
    """
  end

  attr :names, :any, default: nil

  defp names(%{names: :unavailable} = assigns) do
    ~H"""
    <p role="status">Historical names couldn’t be read right now. Refresh to try again.</p>
    """
  end

  defp names(%{names: %{names: []}} = assigns) do
    ~H"""
    <p>No names are recorded for your wallets.</p>
    """
  end

  defp names(assigns) do
    ~H"""
    <ul class="account-names__list">
      <li :for={claim <- @names.names}>
        <div>
          <strong>{claim.fqdn}</strong>
          <span :if={claim.ens_fqdn}>{claim.ens_fqdn}</span>
        </div>
        <div>
          <span>{String.capitalize(claim.claim_status)}</span>
          <span>Claimed {date(claim.created_at)}</span>
        </div>
      </li>
    </ul>
    <p :if={@names.more?}>Showing the first 50 names.</p>
    """
  end

  defp other_wallets(%{wallet_address: primary, wallet_addresses: wallets}) do
    primary = primary && String.downcase(primary)

    wallets
    |> List.wrap()
    |> Enum.map(&String.downcase/1)
    |> Enum.uniq()
    |> Enum.reject(&(&1 == primary))
  end

  # The card names the person the way the header does; the wallet is only
  # repeated beneath when that name is something other than the wallet itself.
  defp short_wallet(%{wallet_address: wallet}) when is_binary(wallet),
    do: PublicIdentity.short_wallet(wallet)

  defp short_wallet(_account), do: nil

  defp date(datetime), do: Calendar.strftime(datetime, "%-d %B %Y")
end
