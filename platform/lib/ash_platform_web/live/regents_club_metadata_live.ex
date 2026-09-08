defmodule AshPlatformWeb.RegentsClubMetadataLive do
  @moduledoc false

  use AshPlatformWeb, :html

  attr :status, :atom, required: true
  attr :wallet, :string, default: nil
  attr :notice, :map, default: nil
  attr :result, :map, default: nil
  attr :review, :map, default: nil

  def page(assigns) do
    ~H"""
    <section
      id="regents-club-metadata-cutover"
      class="metadata-page"
      phx-hook="RegentsClubMetadataWallet"
    >
      <p>Protected one-time action</p>
      <h1>Regents Club metadata cutover</h1>
      <p>
        This page can only prepare the reviewed Base transaction that changes the collection URI
        to <code>https://media.regents.sh/metadata/</code>. Value is always zero. The contract
        enforces signer authorization onchain; this website does not pre-authorize the selected
        wallet.
      </p>

      <p :if={@notice} role={if @notice.tone == :error, do: "alert", else: "status"}>
        {@notice.message}
      </p>

      <AshPlatformWeb.Components.Loading.panel
        :if={@status == :checking}
        id="metadata-readiness-skeleton"
        label="Checking deployment readiness"
        labels={["Privy verification", "Trusted Base RPC"]}
      />

      <section
        :if={@status == :unavailable}
        class="shell-status rg-panel rg-panel--surface rg-panel__body"
        role="alert"
      >
        <h2>Cutover unavailable</h2>
        <p>The protected readiness checks did not pass. Nothing can be prepared or sent.</p>
      </section>

      <section
        :if={@status in [:ready, :observing]}
        class="rg-panel rg-panel--surface rg-panel__body"
        aria-label="Reviewed cutover"
      >
        <dl>
          <div>
            <dt>Network</dt><dd>Base (8453)</dd>
          </div>
          <div>
            <dt>Collection</dt><dd><code>0x2208…D487</code></dd>
          </div>
          <div>
            <dt>Authorization</dt><dd>Enforced by the Regents Club contract onchain</dd>
          </div>
          <div>
            <dt>Value</dt><dd>0 ETH</dd>
          </div>
          <div>
            <dt>Effect</dt><dd>Metadata URI for tokens 1–1998</dd>
          </div>
        </dl>

        <p :if={!@wallet}>Select an Ethereum wallet in Privy before continuing.</p>
        <p :if={@wallet}>Selected Privy wallet: <code>{@wallet}</code></p>
        <p :if={@wallet}>
          If this wallet is not authorized by the contract, the transaction may be mined as a
          contract revert.
        </p>

        <Regent.Primitives.button :if={@wallet} type="button" data-regents-club-metadata-submit>
          {if @status == :observing,
            do: "Review another independent attempt",
            else: "Review with selected wallet"}
        </Regent.Primitives.button>
        <Regent.Primitives.button
          :if={@status == :ready && !@wallet}
          type="button"
          data-regents-club-metadata-connect
        >
          Connect or switch wallet
        </Regent.Primitives.button>
        <p :if={@status == :observing} role="status">
          Existing attempts continue independently while the server checks their finalized Base
          receipt and post-state.
        </p>
      </section>

      <section
        :if={@status == :review && @review}
        class="rg-panel rg-panel--surface rg-panel__body"
        aria-label="Founder transaction review"
      >
        <h2>Confirm the exact reviewed transaction</h2>
        <dl>
          <div>
            <dt>Signer</dt><dd><code>{@review.expected_signer}</code></dd>
          </div>
          <div>
            <dt>Contract</dt><dd><code>{@review.to}</code></dd>
          </div>
          <div>
            <dt>Network</dt><dd>Base (8453)</dd>
          </div>
          <div>
            <dt>Value</dt><dd>0 ETH</dd>
          </div>
          <div>
            <dt>New URI</dt><dd><code>{@review.arguments.new_base_uri}</code></dd>
          </div>
          <div>
            <dt>Calldata Keccak-256</dt><dd><code>{@review.metadata.calldata_keccak256}</code></dd>
          </div>
          <div>
            <dt>Fresh gas estimate</dt><dd>{@review.metadata.gas_estimate}</dd>
          </div>
          <div>
            <dt>Canonical anchor</dt><dd>
              {@review.metadata.anchor_block_number} <code>{@review.metadata.anchor_block_hash}</code>
            </dd>
          </div>
          <div>
            <dt>Effect</dt><dd>Collection-wide metadata update for tokens 1–1998</dd>
          </div>
        </dl>
        <p role="alert">
          {@review.risk_copy} Confirm only after reviewing every value above.
        </p>
        <Regent.Primitives.button
          type="button"
          data-regents-club-metadata-confirm
          data-attempt-id={@review.arguments.attempt_id}
        >
          Confirm and open selected wallet
        </Regent.Primitives.button>
      </section>

      <section
        :if={@status == :unknown}
        class="rg-panel rg-panel--surface rg-panel__body"
        role="alert"
      >
        <h2>Submission outcome unknown</h2>
        <p>
          The attempt was consumed and will not be retried. The bounded trusted-RPC scan did not
          find exactly one matching transaction and event. Manual founder review is required.
        </p>
      </section>

      <section
        :if={@status == :closed}
        class="rg-panel rg-panel--surface rg-panel__body"
        role="status"
      >
        <h2>Cutover finalized and this route is closed</h2>
        <p>
          Trusted Base RPC verified the exact transaction, canonical receipt,
          BatchMetadataUpdate(1, 1998), finalized Base state, and the new boundary token URIs.
          The runtime gate has been disabled on this node. Remove the deployment flag before restart.
        </p>
        <p :if={@result}><code>{@result.transaction_hash}</code></p>
      </section>
    </section>
    """
  end
end
