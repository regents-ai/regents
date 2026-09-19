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
  attr :ens, :atom, default: nil
  attr :names, :any, default: nil
  attr :names_stream, :any, required: true
  attr :claims, :any, default: nil
  attr :claim_name, :map, required: true
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
              <.ens_name account={@account} check={@ens} />
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
          <div class="account-names__heading">
            <h2 id="account-names-title">Claimed Regent Names</h2>
            <p>The names your wallets have claimed, oldest first.</p>
          </div>
          <.names names={@names} stream={@names_stream} />
        </section>

        <section class="account-panel account-claim" aria-labelledby="account-claim-title">
          <div class="account-names__heading">
            <h2 id="account-claim-title">Claim a Regent Name</h2>
            <.claims_available claims={@claims} />
          </div>
          <form
            id="account-claim-form"
            phx-change="check_claim_name"
            phx-submit="check_claim_name"
          >
            <Regent.Primitives.field
              :let={field}
              id="account-claim-name"
              label="Name"
              errors={@claim_name.problems}
            >
              <div class="account-claim__name">
                <input
                  id={field.id}
                  name="name"
                  value={@claim_name.value}
                  autocomplete="off"
                  autocapitalize="none"
                  spellcheck="false"
                  placeholder="yourname"
                  phx-debounce="300"
                  aria-invalid={field.aria_invalid}
                  aria-describedby={field.described_by}
                />
                <span>.regent.eth</span>
              </div>
              <:hint>
                3 to 14 characters: lowercase letters, numbers and hyphens, not starting or ending with a hyphen.
              </:hint>
            </Regent.Primitives.field>
          </form>
          <.claim_name_availability name={@claim_name} />
          <p class="account-claim__later">
            Claiming from this page isn’t open yet. Your free claims are yours to use when it is.
          </p>
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

  # The name Ethereum publishes for the wallet, read for them; a wallet that has
  # not been answered for yet is never shown as having no name.
  attr :account, :map, required: true
  attr :check, :atom, required: true

  defp ens_name(%{account: %{ens_name: name}} = assigns) when is_binary(name) do
    ~H"""
    <dd>{@account.ens_name}</dd>
    """
  end

  defp ens_name(%{account: %{wallet_address: nil}} = assigns) do
    ~H"""
    <dd>No wallet linked</dd>
    """
  end

  defp ens_name(%{check: :checking} = assigns) do
    ~H"""
    <dd role="status">Checking Ethereum for a primary name…</dd>
    """
  end

  defp ens_name(%{check: :unavailable} = assigns) do
    ~H"""
    <dd role="status">Couldn’t check Ethereum right now. Refresh to try again.</dd>
    """
  end

  defp ens_name(assigns) do
    ~H"""
    <dd>No primary name set for this wallet</dd>
    """
  end

  attr :names, :any, default: nil
  attr :stream, :any, required: true

  defp names(%{names: :unavailable} = assigns) do
    ~H"""
    <p role="status">Your claimed names couldn’t be read right now. Refresh to try again.</p>
    """
  end

  defp names(%{names: %{empty?: true}} = assigns) do
    ~H"""
    <p>No names are claimed by your wallets yet.</p>
    """
  end

  # Each claim is shown by its ENS name. The rows come down once and stay in
  # the browser; more are added as the reader reaches the end.
  defp names(assigns) do
    ~H"""
    <ul id="account-names" class="account-names__list" phx-update="stream">
      <li :for={{id, claim} <- @stream} id={id}>
        <strong>{claim.ens_fqdn}</strong>
        <div>
          <span>{String.capitalize(claim.claim_status)}</span>
          <span>Claimed {date(claim.created_at)}</span>
        </div>
      </li>
    </ul>
    <p
      :if={@names.more?}
      id="account-names-more"
      class="account-names__more"
      role="status"
      phx-hook="InfiniteScroll"
      data-event="load_more_names"
      data-cursor={@names.cursor}
    >
      Loading more names…
    </p>
    <p :if={@names.stalled?} role="status">
      More names couldn’t be loaded right now. Refresh to try again.
    </p>
    """
  end

  # How many claims the wallets may still make. A count that could not be read
  # is never shown as none.
  attr :claims, :any, required: true

  defp claims_available(%{claims: :unavailable} = assigns) do
    ~H"""
    <p id="account-claims-available" role="status">
      Your free claims couldn’t be read right now. Refresh to try again.
    </p>
    """
  end

  # The price is the one every paid claim on record was bought at.
  defp claims_available(%{claims: %{free: 0, paid: 0}} = assigns) do
    ~H"""
    <p id="account-claims-available">
      No free claims on your wallets. Names cost 0.0025 ETH each.
    </p>
    """
  end

  defp claims_available(assigns) do
    ~H"""
    <p id="account-claims-available">
      <span :if={@claims.free > 0}>
        You can claim {count(@claims.free, "more name", "more names")} free.
      </span>
      <span :if={@claims.paid > 0}>
        You have {count(@claims.paid, "paid claim", "paid claims")} ready to use.
      </span>
    </p>
    """
  end

  attr :name, :map, required: true

  defp claim_name_availability(%{name: %{availability: :available}} = assigns) do
    ~H"""
    <p id="account-claim-availability" role="status" class="account-claim__available">
      {@name.value}.regent.eth and {@name.value}.agent.base.eth are available.
    </p>
    """
  end

  defp claim_name_availability(%{name: %{availability: :claimed}} = assigns) do
    ~H"""
    <p id="account-claim-availability" role="status" class="account-claim__claimed">
      {@name.value} is already claimed.
    </p>
    """
  end

  defp claim_name_availability(%{name: %{availability: :unavailable}} = assigns) do
    ~H"""
    <p id="account-claim-availability" role="status">
      Couldn’t check whether {@name.value} is claimed right now. Try again in a moment.
    </p>
    """
  end

  defp claim_name_availability(assigns) do
    ~H"""
    <p id="account-claim-availability" role="status" hidden></p>
    """
  end

  defp count(1, singular, _plural), do: "1 #{singular}"
  defp count(n, _singular, plural), do: "#{n} #{plural}"

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
