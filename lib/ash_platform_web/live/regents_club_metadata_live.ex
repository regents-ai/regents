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
    <section id="regents-club-metadata-cutover" phx-hook="RegentsClubMetadataWallet">
      <p>Protected one-time action</p>
      <h1>Regents Club metadata cutover</h1>
      <p>
        This page can only prepare the reviewed Base transaction that changes the collection URI
        to <code>https://media.regents.sh/metadata/</code>. Value is always zero.
      </p>

      <p :if={@notice} role={if @notice.tone == :error, do: "alert", else: "status"}>
        {@notice.message}
      </p>

      <section :if={@status == :checking} class="shell-status" aria-busy="true">
        <h2>Checking deployment readiness</h2>
        <p>Verifying Privy and trusted Base RPC without exposing configuration values.</p>
      </section>

      <section :if={@status == :unavailable} class="shell-status" role="alert">
        <h2>Cutover unavailable</h2>
        <p>The protected readiness checks did not pass. Nothing can be prepared or sent.</p>
      </section>

      <section :if={@status in [:ready, :observing]} aria-label="Reviewed cutover">
        <dl>
          <div>
            <dt>Network</dt><dd>Base (8453)</dd>
          </div>
          <div>
            <dt>Collection</dt><dd><code>0x2208…D487</code></dd>
          </div>
          <div>
            <dt>Owner</dt><dd><code>0x45C9…98E0</code></dd>
          </div>
          <div>
            <dt>Value</dt><dd>0 ETH</dd>
          </div>
          <div>
            <dt>Effect</dt><dd>Metadata URI for tokens 1–1998</dd>
          </div>
        </dl>

        <p :if={!@wallet}>Select the exact owner wallet in Privy before continuing.</p>
        <p :if={@wallet}>Active owner wallet: <code>0x45C9…98E0</code></p>

        <button :if={@wallet} type="button" data-regents-club-metadata-submit>
          {if @status == :observing,
            do: "Review another independent attempt",
            else: "Review in owner wallet"}
        </button>
        <button
          :if={@status == :ready && !@wallet}
          type="button"
          data-regents-club-metadata-connect
        >
          Connect or switch wallet
        </button>
        <p :if={@status == :observing} role="status">
          Existing attempts continue independently while the server checks their finalized Base
          receipt and post-state.
        </p>
      </section>

      <section :if={@status == :review && @review} aria-label="Founder transaction review">
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
        <button
          type="button"
          data-regents-club-metadata-confirm
          data-attempt-id={@review.arguments.attempt_id}
        >
          Confirm and open owner wallet
        </button>
      </section>

      <section :if={@status == :unknown} role="alert">
        <h2>Submission outcome unknown</h2>
        <p>
          The attempt was consumed and will not be retried. The bounded trusted-RPC scan did not
          find exactly one matching transaction and event. Manual founder review is required.
        </p>
      </section>

      <section :if={@status == :closed} role="status">
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
