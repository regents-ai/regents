defmodule AshPlatformWeb.PrivyShowcaseLive do
  @moduledoc """
  Local, executable reference for the Regents Privy integration.

  The router supplies BOTH LocalOnly and the ordinary trusted Session hook.
  Shell.account_control/1 and data-account-target use the production auth_lazy.ts
  dispatcher. PrivyShowcase only observes the existing wallet store and publishes
  its selected address; it never creates a provider, session, signature or payment.
  Wallet reads use the same Ash action as Stake. Only protocol facts are shared.
  """
  use AshPlatformWeb, :live_view

  alias AshPlatform.Staking
  alias AshPlatform.Staking.SnapshotCache
  alias AshPlatform.WalletActions.Address
  alias AshPlatformWeb.Components.{Loading, Shell}
  alias AshPlatformWeb.{ShowcaseLive, TokenDisplay}
  alias Regent.Primitives, as: P

  def mount(_params, session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(AshPlatform.PubSub, SnapshotCache.topic())

    {:ok,
     assign(socket,
       page_title: "Privy integration",
       theme: session["theme"] || "dark",
       mode: ShowcaseLive.privy_mode(),
       protocol: SnapshotCache.snapshot(),
       wallet: nil,
       wallet_facts: nil,
       wallet_status: :idle,
       wallet_generation: 0,
       notice: nil
     ), layout: false}
  end

  def render(assigns) do
    ~H"""
    <link rel="stylesheet" href="/showcase/style.css" />
    <main
      id="privy-reference"
      class="sc privy-reference"
      phx-hook="PrivyShowcase"
      data-privy-enabled={to_string(@mode == :configured)}
    >
      <header class="sc-header privy-reference-header">
        <a class="sc-wordmark" href="/showcase">Regent <span>Workshop</span></a>
        <span class="sc-local">Local only · read-only wallet data</span>
        <%!-- Same markup and event markers as the site header. No second auth handler.
        Profile's in-shell patch link is omitted because this is a different LiveView. --%>
        <Shell.account_control
          account_control={@account_control}
          enabled={@mode == :configured}
          profile_links={false}
        />
        <Shell.theme_toggle id="privy-reference-theme" theme={@theme} />
      </header>

      <div class="privy-reference-content">
        <section class="privy-reference-intro">
          <p class="sc-eyebrow">Regents working reference</p>
          <h1>Privy integration</h1>
          <p>
            Sign in once, connect the wallet you want to use, and watch its data arrive without replacing this page.
          </p>
          <p>No transaction or extra signature is requested by the data panels below.</p>
          <P.button
            type="button"
            disabled={@mode != :configured}
            data-account-target={
              if @account_control.kind == :signed_in, do: "connect-wallet", else: "sign-in"
            }
          >
            {if @account_control.kind == :signed_in,
              do: "Connect or change wallet",
              else: "Sign in with Privy"}
          </P.button>
          <p :if={@mode == :unconfigured} role="status">
            Configure the local Privy app and verification key before using these controls. Nothing is simulated.
          </p>
          <p :if={@mode == :fixture} role="status">
            This server uses a test verifier. Readouts are test data; real sign-in is disabled here.
          </p>
        </section>

        <section class="rg-panel rg-panel--surface" aria-labelledby="privy-state-heading">
          <h2 id="privy-state-heading">Account and wallet</h2>
          <dl class="privy-reference-facts">
            <div>
              <dt>Regents session</dt><dd id="privy-session-state">
                {if @account_control.kind == :signed_in, do: "Signed in", else: "Signed out"}
              </dd>
            </div>
            <div>
              <dt>Account</dt><dd>{@account_control.label}</dd>
            </div>
            <div>
              <dt>Selected connected wallet</dt><dd id="privy-selected-wallet">
                {@wallet || "No wallet selected"}
              </dd>
            </div>
            <div>
              <dt>Wallet data</dt><dd id="privy-wallet-status">{wallet_status(@wallet_status)}</dd>
            </div>
          </dl>
          <P.button
            type="button"
            disabled={@mode != :configured}
            data-account-target={
              if @account_control.kind == :signed_in, do: "connect-wallet", else: "sign-in"
            }
          >
            Connect wallet
          </P.button>
          <p>
            Signing in and having a transaction-ready wallet are separate states. Disconnect in the header clears this wallet selection and its readout.
          </p>
        </section>

        <section class="rg-panel rg-panel--surface" aria-labelledby="privy-wallet-heading">
          <h2 id="privy-wallet-heading">Wallet data hydration</h2>
          <p :if={is_nil(@wallet)}>Connect a wallet to load its current Base balances.</p>
          <Loading.panel
            :if={@wallet_status == :loading && is_nil(@wallet_facts)}
            id="privy-wallet-skeleton"
            label="Reading Base"
            labels={["Available REGENT", "Staked REGENT", "Claimable USDC"]}
          />
          <dl
            :if={@wallet_facts}
            id="privy-wallet-readout"
            class="privy-reference-facts"
            aria-busy={to_string(@wallet_status == :loading)}
          >
            <div>
              <dt>Wallet block</dt><dd>{TokenDisplay.count(@wallet_facts.wallet_block_number)}</dd>
            </div>
            <div>
              <dt>Available REGENT</dt><dd>
                <TokenDisplay.amount amount={@wallet_facts.wallet_token_balance} unit="REGENT" />
              </dd>
            </div>
            <div>
              <dt>Staked REGENT</dt><dd>
                <TokenDisplay.amount amount={@wallet_facts.wallet_stake_balance} unit="REGENT" />
              </dd>
            </div>
            <div>
              <dt>Claimable USDC</dt><dd>
                <TokenDisplay.amount amount={@wallet_facts.wallet_claimable_usdc} unit="USDC" />
              </dd>
            </div>
            <div>
              <dt>Claimable REGENT</dt><dd>
                <TokenDisplay.amount amount={@wallet_facts.wallet_claimable_regent} unit="REGENT" />
              </dd>
            </div>
          </dl>
          <p :if={@notice} role="status">{@notice}</p>
          <P.button
            type="button"
            phx-click="refresh_data"
            disabled={is_nil(@wallet) || @wallet_status == :loading}
          >
            {if @wallet_status == :loading, do: "Refreshing…", else: "Refresh Data"}
          </P.button>
          <p>
            Refresh reads this wallet again. When signed in, it also refreshes the protocol cache used by other visitors.
          </p>
        </section>

        <section class="rg-panel rg-panel--surface" aria-labelledby="privy-protocol-heading">
          <h2 id="privy-protocol-heading">Shared protocol data</h2>
          <Loading.panel
            :if={is_nil(@protocol)}
            id="privy-protocol-skeleton"
            label="Waiting for the shared reading"
          />
          <dl :if={@protocol} id="privy-protocol-readout" class="privy-reference-facts">
            <div>
              <dt>Base block</dt><dd>{TokenDisplay.count(@protocol.block_number)}</dd>
            </div>
            <div>
              <dt>Total REGENT staked</dt><dd>
                <TokenDisplay.amount amount={@protocol.total_staked} unit="REGENT" />
              </dd>
            </div>
          </dl>
          <p>
            This cache contains protocol facts only. Wallet balances stay with this page and are discarded when the selected wallet changes.
          </p>
        </section>

        <section
          class="rg-panel rg-panel--surface privy-reference-setup"
          aria-labelledby="privy-setup-heading"
        >
          <h2 id="privy-setup-heading">Setup and source map</h2>
          <ol>
            <li>Enable wallet login in your Privy app and admit your exact localhost origin.</li>
            <li>
              Provide <code>PRIVY_APP_ID</code>
              and <code>PRIVY_VERIFICATION_KEY</code>
              to the development process. Never put an app secret in browser code.
            </li>
            <li>
              Create your local PostgreSQL database (<code>ash_platform_dev</code>
              by default), then run <code>mix ash_platform.setup_local_auth</code>. Use <code>MIX_ENV=dev</code>, not a browser-test server, for real sign-in.
            </li>
            <li>
              Build the assets with <code>mix assets.build</code>, start <code>mix phx.server</code>, then open <code>/showcase/privy</code>.
            </li>
            <li>
              <code>BASE_READ_RPC_URL</code>
              selects the Base reader; <code>ETHEREUM_READ_RPC_URL</code>
              enables ENS lookups. Values are never displayed here.
            </li>
          </ol>
          <details>
            <summary>Which file owns each step?</summary>
            <ul>
              <li>
                <code>components/shell.ex · account_control/1</code>: the shared Regents header markup.
              </li>
              <li>
                <code>assets/js/auth_lazy.ts</code>: one document-level button dispatcher and server-session coordination.
              </li>
              <li>
                <code>assets/js/privy_bridge.tsx</code>: the existing Privy SDK hooks, selection and logout handling.
              </li>
              <li>
                <code>assets/js/hooks/privy_showcase.ts</code>: observes wallet state; no authentication implementation.
              </li>
              <li>
                <code>live/privy_showcase_live.ex</code>: this page's read-only Ash calls, cancellation and hydration.
              </li>
              <li>
                <code>live/session.ex</code>: verified server identity; browser wallet addresses do not grant authority.
              </li>
            </ul>
          </details>
          <p>
            Shared presentation lives in <code>design-system/regent_ui</code>. Shared identity lives in <code>regents/identity</code>; token verification lives in <code>elixir-utils/privy</code>. The browser integration shown here remains Regents-owned.
          </p>
          <a
            href="https://docs.privy.io/authentication/user-authentication/logout"
            target="_blank"
            rel="noopener noreferrer"
          >Privy logout documentation ↗</a>
        </section>
      </div>
    </main>
    """
  end

  # The address is a public read target, never proof of authentication. Session
  # authority is independently supplied and rechecked by Live.Session.
  def handle_event("privy_wallet_changed", %{"address" => address}, socket) do
    wallet =
      case Address.normalize(address) do
        {:ok, wallet} -> wallet
        :error -> nil
      end

    if wallet == socket.assigns.wallet do
      {:noreply, socket}
    else
      socket = cancel_wallet_read(socket)

      {:noreply,
       socket
       |> assign(wallet: wallet, wallet_facts: nil, wallet_status: :idle, notice: nil)
       |> read_wallet()}
    end
  end

  def handle_event("refresh_data", _params, socket) do
    notice =
      if socket.assigns.account_control.kind == :signed_in do
        case SnapshotCache.refresh() do
          :ok ->
            nil

          {:error, :refresh_too_soon} ->
            "Protocol data was refreshed recently. Your wallet is still refreshed."
        end
      end

    {:noreply, socket |> assign(:notice, notice) |> cancel_wallet_read() |> read_wallet()}
  end

  def handle_info({:staking_snapshot, protocol}, socket),
    do: {:noreply, assign(socket, :protocol, protocol)}

  def handle_info(_message, socket), do: {:noreply, socket}

  # Each read has its own generation. An old result cannot repopulate the panel
  # after a wallet switch, logout or another refresh.
  def handle_async(
        {:privy_wallet, generation},
        {:ok, {:ok, facts}},
        %{assigns: %{wallet_generation: generation}} = socket
      ),
      do: {:noreply, assign(socket, wallet_facts: facts, wallet_status: :ready)}

  def handle_async(
        {:privy_wallet, generation},
        _failed,
        %{assigns: %{wallet_generation: generation}} = socket
      ),
      do:
        {:noreply,
         assign(socket,
           wallet_status: :error,
           notice: "This wallet could not be refreshed. Any previous reading is still shown."
         )}

  def handle_async(_name, _result, socket), do: {:noreply, socket}

  defp cancel_wallet_read(socket) do
    socket =
      if socket.assigns.wallet_status == :loading,
        do: cancel_async(socket, {:privy_wallet, socket.assigns.wallet_generation}),
        else: socket

    assign(socket, :wallet_generation, socket.assigns.wallet_generation + 1)
  end

  defp read_wallet(%{assigns: %{wallet: nil}} = socket), do: socket

  defp read_wallet(socket) do
    wallet = socket.assigns.wallet

    socket
    |> assign(:wallet_status, :loading)
    |> start_async({:privy_wallet, socket.assigns.wallet_generation}, fn ->
      Staking.account_for_wallet(wallet)
    end)
  end

  defp wallet_status(:idle), do: "No wallet selected"
  defp wallet_status(:loading), do: "Loading current balances"
  defp wallet_status(:ready), do: "Current reading loaded"
  defp wallet_status(:error), do: "Refresh unavailable"
end
