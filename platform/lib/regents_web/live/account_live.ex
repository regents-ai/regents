defmodule RegentsWeb.AccountLive do
  @moduledoc """
  The signed-in person's Account, one tab each: Account (their profile, their
  Credits, the agents they paired and pairing a new one, in the layout every
  Regent site shares, `Regent.Account.layout`), Wallets (the wallets their sign-in
  verified) and Connections (the accounts they have connected). Points has its own tab (`RegentsWeb.PointsLive`).

  Everything here is read from the sign-in the shell already holds; nothing on
  the page asks the visitor to sign in again.
  """

  use RegentsWeb, :html

  import RegentsWeb.Components.PageHead, only: [page_head: 1]
  import RegentsWeb.Components.VerifiedConnections

  attr :lease, :map, required: true
  attr :account, :map, default: nil
  attr :signed_out_reason, :atom, default: :signed_out
  attr :account_control, :map, required: true
  attr :credits_read, RegentsWeb.Read, default: %RegentsWeb.Read{}

  def profile(assigns) do
    ~H"""
    <.settings_page
      id="account-page"
      title="Account"
      account={@account}
      signed_out_reason={@signed_out_reason}
    >
      <:tip>Your profile, your Credits and your agents.</:tip>
      <Regent.Account.layout id="account">
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
                id="account-identity-picture"
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
          <.live_component
            module={RegentsWeb.AgentsPanel}
            id="account-agents"
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
          <Regent.Account.credits_summary
            id="account-credits"
            available={
              @credits_read.value && RegentCredits.Amount.format(@credits_read.value.available)
            }
            held={@credits_read.value && RegentCredits.Amount.format(@credits_read.value.held)}
            state={if @credits_read.state in [:idle, :empty], do: :loading, else: @credits_read.state}
          >
            <.link patch="/account/credits">Manage Credits on regents.sh</.link>
          </Regent.Account.credits_summary>
        </:credits>
        <:profile>
          <%!-- The name is saved from the browser with the sign-in's own proof. --%>
          <div id="account-profile" phx-hook="PublicName" phx-update="ignore">
            <Regent.Profile.panel
              id="account-public-name"
              class="account-panel"
              display_name={@account.display_name}
            />
          </div>
        </:profile>
      </Regent.Account.layout>
    </.settings_page>
    """
  end

  attr :account, :map, default: nil
  attr :signed_out_reason, :atom, default: :signed_out
  attr :sign_in_wallets, :map, required: true

  def wallets(assigns) do
    assigns = assign(assigns, :named, named_wallets(assigns.account, assigns.sign_in_wallets))

    ~H"""
    <.settings_page
      id="wallets-page"
      title="Wallets"
      account={@account}
      signed_out_reason={@signed_out_reason}
    >
      <:tip>The wallets your sign-in verified.</:tip>
      <section class="account-panel account-details" aria-labelledby="account-wallets-title">
        <h2 id="account-wallets-title">Your wallets</h2>
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
        </dl>
      </section>
    </.settings_page>
    """
  end

  attr :account, :map, default: nil
  attr :signed_out_reason, :atom, default: :signed_out
  attr :verified_connections, RegentsWeb.Read, required: true
  attr :verified_connections_notice, :map, default: nil

  def connections(assigns) do
    ~H"""
    <.settings_page
      id="connections-page"
      title="Connections"
      account={@account}
      signed_out_reason={@signed_out_reason}
    >
      <:tip>Accounts you have connected, such as X, GitHub and Farcaster.</:tip>
      <.verified_connections
        id="account-verified-connections"
        class="account-panel"
        identities={@verified_connections.value}
        read_state={@verified_connections.state}
        notice={@verified_connections_notice}
      />
    </.settings_page>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :account, :map, default: nil
  attr :signed_out_reason, :atom, default: :signed_out
  slot :tip, required: true
  slot :inner_block, required: true

  defp settings_page(assigns) do
    ~H"""
    <article id={@id} class="account-page rg-utility">
      <.page_head title={@title}>
        <:tip>{render_slot(@tip)}</:tip>
      </.page_head>

      <Regent.Account.signed_out
        :if={is_nil(@account)}
        id={"#{@id}-signed-out"}
        reason={@signed_out_reason}
      >
        <:sign_in>
          <Regent.Primitives.button type="button" data-account-target="sign-in">
            Sign in
          </Regent.Primitives.button>
        </:sign_in>
      </Regent.Account.signed_out>

      {@account && render_slot(@inner_block)}
    </article>
    """
  end

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
end
