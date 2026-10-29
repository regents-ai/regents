defmodule RegentsWeb.AccountLive do
  @moduledoc """
  The signed-in person's own page, in the layout every Regent site shares
  (`Regent.Account.layout`): this site's own sections first (the names the
  wallets hold and may claim, and the accounts they have connected), then who
  the site knows them as, the agents they have paired with the pairing box, and
  their Credits over their details (the wallets their sign-in verified, their
  names and World ID) in the profile's place.

  Everything here is read from the sign-in the shell already holds; nothing on
  the page asks the visitor to sign in again.
  """

  use RegentsWeb, :html

  import RegentsWeb.Components.PairedAgents
  import RegentsWeb.Components.VerifiedConnections

  attr :lease, :map, required: true
  attr :account, :map, default: nil
  attr :signed_out_reason, :atom, required: true
  attr :account_control, :map, required: true
  attr :ens, :atom, default: nil
  attr :names, :any, default: nil
  attr :names_stream, :any, required: true
  attr :claims, :any, default: nil
  attr :claim_name, :map, required: true
  attr :verified_connections, :list, default: []
  attr :verified_connections_notice, :map, default: nil
  attr :agents, :any, default: nil
  attr :agent_detail, :map, default: nil
  attr :agent_notice, :any, default: nil
  attr :agents_now, DateTime, default: nil
  attr :sign_in_wallets, :map, required: true

  attr :credits, :map,
    required: true,
    doc: "The account's Credits balance read: its state and value (`RegentCredits.balance/1`)."

  def page(assigns) do
    assigns = assign(assigns, :named, named_wallets(assigns.account, assigns.sign_in_wallets))

    ~H"""
    <article id="account-page" class="account-page">
      <header class="account-heading">
        <p class="account-kicker">Regents Labs</p>
        <h1 tabindex="-1">Account</h1>
        <p class="account-lede">
          The wallet you signed in with, your agents, the names it holds and the accounts you have connected.
        </p>
      </header>

      <Regent.Account.signed_out
        :if={is_nil(@account)}
        id="account-signed-out"
        reason={@signed_out_reason}
      >
        <:sign_in>
          <Regent.Primitives.button type="button" data-account-target="sign-in">
            Sign in
          </Regent.Primitives.button>
        </:sign_in>
      </Regent.Account.signed_out>

      <Regent.Account.layout :if={@account} id="account">
        <:site>
          <section class="account-panel account-names" aria-labelledby="account-names-title">
            <div class="account-names__heading">
              <h2 id="account-names-title">Claimed Regent Names</h2>
              <p>The names your wallets have claimed, oldest first.</p>
            </div>
            <.names names={@names} stream={@names_stream} />
          </section>
        </:site>
        <:site>
          <section class="account-panel account-claim" aria-labelledby="account-claim-title">
            <div class="account-names__heading">
              <h2 id="account-claim-title">Claim a Regent Name</h2>
              <.claims_available claims={@claims} />
            </div>
            <form
              id="account-claim-form"
              phx-change="check_claim_name"
              phx-submit="claim_name"
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
              <Regent.Primitives.button
                id="account-claim-submit"
                type="submit"
                disabled={not claimable?(@claims, @claim_name)}
                phx-disable-with="Claiming…"
              >
                Claim name
              </Regent.Primitives.button>
            </form>
            <.claim_name_availability name={@claim_name} />
            <%!-- The price is the one every paid claim on record was bought at. --%>
            <p :if={match?(%{free: 0}, @claims)} class="account-claim__later">
              Names cost 0.0025 ETH each, and buying one from this page isn’t open yet.
            </p>
          </section>
        </:site>
        <:site>
          <.verified_connections
            id="account-verified-connections"
            class="account-panel"
            identities={@verified_connections}
            notice={@verified_connections_notice}
          />
        </:site>
        <:identity>
          <Regent.Account.identity
            id="account-identity"
            name={@account_control.label}
            wallet={@account_control.wallet}
            ens_name={@account_control.ens_name}
          >
            <:picture>
              <img
                :if={@account_control.avatar_src}
                src={@account_control.avatar_src}
                referrerpolicy="no-referrer"
                width="64"
                height="64"
                alt=""
              />
            </:picture>
          </Regent.Account.identity>
        </:identity>
        <:agents>
          <.paired_agents
            agents={@agents}
            detail={@agent_detail}
            notice={@agent_notice}
            now={@agents_now}
            lease={@lease}
            account={@account}
          />
        </:agents>
        <:pairing>
          <.live_component
            module={RegentsWeb.PairingBox}
            id="account-pairing-box"
            lease={@lease}
            account={@account}
          />
        </:pairing>
        <:credits>
          <div id="account-credits" class="account-panel account-credits">
            <Regent.Account.credits_summary
              id="account-credits-summary"
              available={@credits.value && RegentCredits.Amount.format(@credits.value.available)}
              held={@credits.value && RegentCredits.Amount.format(@credits.value.held)}
              state={credits_state(@credits.state)}
            >
              <div class="account-credits__more">
                <p>One balance for every Regent site. One Credit is one US dollar.</p>
                <div class="account-credits__actions">
                  <Regent.Primitives.button
                    type="button"
                    phx-click={Phoenix.LiveView.JS.dispatch("regents:open", to: "#shell-credits")}
                  >
                    Buy Credits
                  </Regent.Primitives.button>
                  <.link navigate="/account/credits">Purchase History</.link>
                  <.link navigate="/account/points">Points</.link>
                </div>
              </div>
            </Regent.Account.credits_summary>

            <h3>What your agents may spend</h3>
            <.live_component
              module={RegentsWeb.CreditsAgentSpending}
              id="account-agent-spending"
              lease={@lease}
              account={@account}
              agents={agent_wallets(@agents)}
              sites={Regents.Credits.agent_sites()}
            />
          </div>
        </:credits>
        <:profile>
          <section class="account-panel account-details" aria-labelledby="account-details-title">
            <h2 id="account-details-title">Details</h2>
            <dl>
              <div :if={@named.user}>
                <dt>User wallet</dt>
                <dd>
                  <Regent.Primitives.address id="account-user-wallet" address={@named.user} />
                </dd>
              </div>
              <div>
                <dt>Regents embedded wallet</dt>
                <dd :if={@named.embedded}>
                  <Regent.Primitives.address id="account-embedded-wallet" address={@named.embedded} />
                </dd>
                <dd :if={is_nil(@named.embedded)}>Made for you at your next sign-in</dd>
              </div>
              <div :if={@named.others != []}>
                <dt>Other linked wallets</dt>
                <dd>
                  <ul class="account-wallet-list">
                    <li :for={wallet <- @named.others}>
                      <Regent.Primitives.address id={"account-wallet-#{wallet}"} address={wallet} />
                    </li>
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
        </:profile>
      </Regent.Account.layout>
    </article>
    """
  end

  # A balance not asked for yet is on its way.
  defp credits_state(:idle), do: :loading
  defp credits_state(state), do: state

  # The wallets of the agents paired to this account, which may be given Credits to spend.
  defp agent_wallets(agents) when is_list(agents), do: Enum.map(agents, &{&1.wallet, &1.name})
  defp agent_wallets(_unread), do: []

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
    <ul
      id="account-names"
      class="account-names__list"
      phx-update="stream"
      phx-hook="MotionList"
      data-layout-id="account-names"
      data-children="li"
      data-variant={RegentsWeb.Motion.standard("list")}
    >
      <li :for={{id, claim} <- @stream} id={id} data-layout-id={id}>
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

  # Only free claims can be spent here; paid claims are counted but not usable.
  defp claims_available(assigns) do
    ~H"""
    <p id="account-claims-available">
      <span :if={@claims.free > 0}>
        You can claim {count(@claims.free, "more name", "more names")} free.
      </span>
      <span :if={@claims.free == 0}>No free claims on your wallets.</span>
      <span :if={@claims.paid > 0}>
        You also have {count(@claims.paid, "paid claim", "paid claims")}, which this page can’t use yet.
      </span>
    </p>
    """
  end

  attr :name, :map, required: true

  defp claim_name_availability(%{name: %{availability: :available}} = assigns) do
    ~H"""
    <p id="account-claim-availability" role="status" class="account-claim__available">
      {@name.value}.regent.eth is available.
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

  defp claim_name_availability(%{name: %{availability: {:claimed_now, _name}}} = assigns) do
    ~H"""
    <p id="account-claim-availability" role="status" class="account-claim__available">
      {elem(@name.availability, 1)} is yours.
    </p>
    """
  end

  defp claim_name_availability(%{name: %{availability: :not_claimed}} = assigns) do
    ~H"""
    <p id="account-claim-availability" role="status" class="account-claim__claimed">
      Couldn’t claim {@name.value}.regent.eth right now. Try again in a moment.
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

  # The button waits for a name that passed every check and a free claim to
  # spend on it; the lines beside it say which of the two is missing.
  defp claimable?(%{free: free}, %{availability: :available}) when free > 0, do: true
  defp claimable?(_claims, _claim_name), do: false

  defp count(1, singular, _plural), do: "1 #{singular}"
  defp count(n, _singular, plural), do: "#{n} #{plural}"

  # The sign-in names which linked wallet Privy made for the person and which is
  # their own. A name for a wallet the account no longer holds is not shown, so
  # an outside wallet is never shown as the Regents wallet.
  defp named_wallets(nil, _sign_in_wallets), do: %{user: nil, embedded: nil, others: []}

  defp named_wallets(%{wallet_addresses: wallets}, sign_in_wallets) do
    linked = wallets |> List.wrap() |> Enum.map(&String.downcase/1) |> Enum.uniq()
    named = fn key -> if sign_in_wallets[key] in linked, do: sign_in_wallets[key] end
    user = named.("user")
    embedded = named.("embedded")

    %{user: user, embedded: embedded, others: linked -- [user, embedded]}
  end

  defp date(datetime), do: Calendar.strftime(datetime, "%-d %B %Y")
end
