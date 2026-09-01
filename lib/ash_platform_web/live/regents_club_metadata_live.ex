defmodule AshPlatformWeb.RegentsClubMetadataLive do
  @moduledoc false

  use AshPlatformWeb, :live_view

  import AshPlatformWeb.Components.Shell

  alias AshPlatform.RegentsClub
  alias AshPlatform.RegentsClub.Actions
  alias AshPlatform.WalletActions.Address
  alias AshPlatformWeb.Plugs.LaunchGate
  alias AshPlatformWeb.RouteCatalog

  @observation_interval 15_000

  @impl true
  def mount(params, _session, socket) do
    if RegentsClub.enabled?() and authenticated?(socket.assigns.access_context) do
      route_spec = RouteCatalog.fetch!(socket.assigns.live_action, params)

      socket =
        socket
        |> assign(
          app_targets: open_app_targets(),
          route_spec: route_spec,
          status: :checking,
          wallet: nil,
          route_notice: nil,
          attempts: %{},
          result: nil,
          shell_instance: System.unique_integer([:positive, :monotonic])
        )
        |> stream(:attempts, [])

      {:ok, if(connected?(socket), do: start_readiness(socket), else: socket)}
    else
      {:ok, redirect(socket, to: "/")}
    end
  end

  @impl true
  def handle_async(:readiness, {:ok, {:ok, %{state: :ready}}}, socket) do
    {:noreply, assign(socket, status: :ready, route_notice: nil)}
  end

  def handle_async(:readiness, {:ok, {:ok, %{state: :changed_unverified}}}, socket) do
    {:noreply,
     assign(socket,
       status: :unknown,
       route_notice: notice(:changed_unverified)
     )}
  end

  def handle_async(:readiness, _result, socket) do
    {:noreply, assign(socket, status: :unavailable, route_notice: notice(:readiness_failed))}
  end

  def handle_async({:prepare, attempt_id}, {:ok, {:ok, envelope}}, socket) do
    update_attempt(socket, attempt_id, fn attempt ->
      %{attempt | phase: :review, envelope: envelope, notice: nil}
    end)
  end

  def handle_async({:prepare, attempt_id}, {:ok, {:error, reason}}, socket),
    do: refuse_attempt(socket, attempt_id, reason)

  def handle_async({:prepare, attempt_id}, _result, socket),
    do: refuse_attempt(socket, attempt_id, :readiness_failed)

  def handle_async({:confirm, attempt_id}, {:ok, {:ok, envelope}}, socket) do
    socket =
      update_attempt_value(socket, attempt_id, fn attempt ->
        %{attempt | phase: :handed_off, envelope: envelope, notice: nil}
      end)

    {:noreply,
     push_event(socket, "regents-club-metadata:prepared", %{
       attempt_id: attempt_id,
       envelope: envelope
     })}
  end

  def handle_async({:confirm, attempt_id}, {:ok, {:error, reason}}, socket),
    do: refuse_attempt(socket, attempt_id, reason)

  def handle_async({:confirm, attempt_id}, _result, socket),
    do: refuse_attempt(socket, attempt_id, :readiness_failed)

  def handle_async({:observe, attempt_id}, {:ok, {:ok, {:finalized, result}}}, socket) do
    RegentsClub.disable!()

    socket =
      socket
      |> update_attempt_value(attempt_id, fn attempt ->
        %{attempt | phase: :finalized, result: result, notice: notice(:finalized)}
      end)
      |> assign(status: :closed, result: result, route_notice: notice(:finalized))

    {:noreply, socket}
  end

  def handle_async({:observe, attempt_id}, {:ok, {:ok, :pending}}, socket) do
    case socket.assigns.attempts[attempt_id] do
      %{phase: :observing, envelope: envelope} ->
        if Actions.observation_open?(envelope) do
          Process.send_after(
            self(),
            {:observe_regents_club_metadata, attempt_id},
            @observation_interval
          )

          {:noreply, socket}
        else
          {:noreply, unknown_attempt(socket, attempt_id)}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_async({:observe, attempt_id}, {:ok, {:ok, :reverted}}, socket) do
    {:noreply,
     update_attempt_value(socket, attempt_id, fn attempt ->
       %{attempt | phase: :reverted, notice: notice(:reverted)}
     end)}
  end

  def handle_async({:observe, attempt_id}, _result, socket) do
    {:noreply, unknown_attempt(socket, attempt_id)}
  end

  @impl true
  def handle_event("regents_club_metadata_active_wallet", params, socket) do
    wallet =
      if authenticated?(socket.assigns.access_context),
        do: normalized_wallet(params["address"])

    {:noreply, assign(socket, wallet: wallet)}
  end

  def handle_event(
        "prepare_regents_club_metadata",
        %{"address" => address, "attempt_id" => attempt_id},
        %{assigns: %{status: :ready, attempts: attempts}} = socket
      ) do
    wallet = normalized_wallet(address)

    if wallet && RegentsClub.valid_attempt_id?(attempt_id) && !Map.has_key?(attempts, attempt_id) do
      attempt = %{
        id: attempt_id,
        phase: :preparing,
        envelope: nil,
        hash: nil,
        recovery: false,
        notice: nil,
        result: nil
      }

      lease = socket.assigns.session_lease

      {:noreply,
       socket
       |> put_attempt(attempt)
       |> start_async({:prepare, attempt_id}, fn -> Actions.prepare(wallet, attempt_id, lease) end)}
    else
      {:noreply, push_event(socket, "regents-club-metadata:refused", %{attempt_id: attempt_id})}
    end
  end

  def handle_event("prepare_regents_club_metadata", _params, socket), do: {:noreply, socket}

  def handle_event("confirm_regents_club_metadata", %{"attempt_id" => attempt_id}, socket) do
    case socket.assigns.attempts[attempt_id] do
      %{phase: :review, envelope: envelope} = attempt ->
        wallet = socket.assigns.wallet

        if Address.equal?(wallet, envelope.expected_signer) do
          lease = socket.assigns.session_lease

          {:noreply,
           socket
           |> put_attempt(%{attempt | phase: :confirming, notice: nil})
           |> start_async({:confirm, attempt_id}, fn ->
             Actions.prepare(wallet, attempt_id, lease)
           end)}
        else
          refuse_attempt(socket, attempt_id, :wallet_changed)
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event(
        "regents_club_metadata_submitted",
        %{"attempt_id" => attempt_id, "hash" => hash},
        socket
      ) do
    observe_attempt(socket, attempt_id, %{hash: hash, recovery: false}, fn envelope ->
      Actions.observe_hash(envelope, hash)
    end)
  end

  def handle_event(
        "regents_club_metadata_submission_unknown",
        %{"attempt_id" => attempt_id},
        socket
      ) do
    case socket.assigns.attempts[attempt_id] do
      %{phase: :handed_off} -> {:noreply, unknown_attempt(socket, attempt_id)}
      _ -> {:noreply, socket}
    end
  end

  def handle_event(event, %{"attempt_id" => attempt_id}, socket)
      when event in ["regents_club_metadata_cancelled", "regents_club_metadata_refused"] do
    kind = if event == "regents_club_metadata_cancelled", do: :cancelled, else: :browser_refused

    {:noreply,
     update_attempt_value(socket, attempt_id, fn attempt ->
       %{attempt | phase: kind, notice: notice(kind)}
     end)}
  end

  def handle_event("regents_club_metadata_browser_refused", _params, socket) do
    {:noreply, assign(socket, route_notice: notice(:browser_refused))}
  end

  @impl true
  def handle_info({:observe_regents_club_metadata, attempt_id}, socket) do
    case socket.assigns.attempts[attempt_id] do
      %{phase: :observing} = attempt ->
        {:noreply,
         start_async(socket, {:observe, attempt_id}, fn -> observe_attempt_result(attempt) end)}

      _ ->
        {:noreply, socket}
    end
  end

  defp observe_attempt_result(%{envelope: envelope, hash: hash}),
    do: Actions.observe_hash(envelope, hash)

  @impl true
  def render(assigns) do
    ~H"""
    <.shell
      route_spec={@route_spec}
      app_targets={@app_targets}
      account_control={@account_control}
      content_status={if @status == :checking, do: :loading, else: :ready}
      presentation={:none}
      shell_instance={@shell_instance}
      navigation={:navigate}
    >
      <:content>
        <section id="regents-club-metadata-cutover" phx-hook="RegentsClubMetadataWallet">
          <p>Protected one-time action</p>
          <h1>Regents Club metadata cutover</h1>
          <p>
            This page prepares one zero-value Base transaction. The contract decides whether the
            selected wallet is authorized; the website does not pre-authorize it.
          </p>

          <p :if={@route_notice} role={notice_role(@route_notice)}>
            {@route_notice.message}
          </p>

          <section :if={@status == :checking} class="shell-status" aria-busy="true">
            <h2>Checking the current release</h2>
            <p>Checking representative media and the current Base contract snapshot.</p>
          </section>

          <section :if={@status == :unavailable} class="shell-status" role="alert">
            <h2>Cutover unavailable</h2>
            <p>The current checks did not pass. Nothing can be prepared or sent.</p>
          </section>

          <section :if={@status == :ready} aria-label="Reviewed cutover">
            <dl>
              <div>
                <dt>Network</dt><dd>Base (8453)</dd>
              </div>
              <div>
                <dt>Collection</dt><dd><code>0x2208…D487</code></dd>
              </div>
              <div>
                <dt>Authorization</dt><dd>Enforced by the contract onchain</dd>
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
              An unauthorized wallet can still open its own wallet request; the contract will decide
              the result.
            </p>

            <button :if={@wallet} type="button" data-regents-club-metadata-submit>
              Review with selected wallet
            </button>
            <button :if={!@wallet} type="button" data-regents-club-metadata-connect>
              Connect or switch wallet
            </button>
          </section>

          <div id="regents-club-metadata-attempts" phx-update="stream">
            <section
              :for={{dom_id, attempt} <- @streams.attempts}
              id={dom_id}
              data-attempt-id={attempt.id}
              data-attempt-phase={attempt.phase}
            >
              <p :if={attempt.notice} role={notice_role(attempt.notice)}>
                {attempt.notice.message}
              </p>

              <p :if={attempt.phase in [:preparing, :confirming]} aria-busy="true">
                {if attempt.phase == :preparing,
                  do: "Reading the current release for this attempt…",
                  else: "Rechecking this attempt before wallet handoff…"}
              </p>

              <.attempt_review :if={attempt.phase == :review} attempt={attempt} />

              <p :if={attempt.phase == :handed_off} role="status">
                This attempt is open in the selected wallet.
              </p>

              <p :if={attempt.phase == :observing} role="status">
                This attempt is waiting for its own finalized Base result.
              </p>

              <section :if={attempt.phase == :unknown} role="alert">
                <h2>Submission outcome unknown</h2>
                <p>Manual founder review is required for this attempt.</p>
              </section>

              <p :if={attempt.phase == :finalized && attempt.result}>
                Finalized transaction: <code>{attempt.result.transaction_hash}</code>
              </p>
            </section>
          </div>

          <section :if={@status == :closed} role="status">
            <h2>Cutover finalized and this route is closed</h2>
            <p>
              Trusted Base RPC verified the exact transaction, event, finalized state, and new token
              URI boundaries. Remove the temporary deployment flag before restart.
            </p>
            <p :if={@result}><code>{@result.transaction_hash}</code></p>
          </section>
        </section>
      </:content>
    </.shell>
    """
  end

  attr :attempt, :map, required: true

  defp attempt_review(assigns) do
    ~H"""
    <section
      aria-label="Founder transaction review"
      data-anchor-block={@attempt.envelope.metadata.anchor_block_number}
    >
      <h2>Confirm the exact reviewed transaction</h2>
      <dl>
        <div>
          <dt>Signer</dt><dd><code>{@attempt.envelope.expected_signer}</code></dd>
        </div>
        <div>
          <dt>Contract</dt><dd><code>{@attempt.envelope.to}</code></dd>
        </div>
        <div>
          <dt>Network</dt><dd>Base (8453)</dd>
        </div>
        <div>
          <dt>Value</dt><dd>0 ETH</dd>
        </div>
        <div>
          <dt>New URI</dt><dd><code>{@attempt.envelope.arguments.new_base_uri}</code></dd>
        </div>
        <div>
          <dt>Calldata Keccak-256</dt>
          <dd><code>{@attempt.envelope.metadata.calldata_keccak256}</code></dd>
        </div>
        <div>
          <dt>Fresh gas estimate</dt><dd>{@attempt.envelope.metadata.gas_estimate}</dd>
        </div>
        <div>
          <dt>Canonical anchor</dt>
          <dd>
            {@attempt.envelope.metadata.anchor_block_number}
            <code>{@attempt.envelope.metadata.anchor_block_hash}</code>
          </dd>
        </div>
      </dl>
      <p role="alert">
        {@attempt.envelope.risk_copy} Confirm only after reviewing every value above.
      </p>
      <button
        type="button"
        data-regents-club-metadata-confirm
        data-attempt-id={@attempt.id}
      >
        Confirm and open selected wallet
      </button>
    </section>
    """
  end

  defp start_readiness(socket) do
    lease = socket.assigns.session_lease
    start_async(socket, :readiness, fn -> Actions.deployment_readiness(lease) end)
  end

  defp observe_attempt(socket, attempt_id, fields, observer) do
    case socket.assigns.attempts[attempt_id] do
      %{phase: :handed_off, envelope: envelope} = attempt ->
        if Actions.observation_open?(envelope) do
          attempt = attempt |> Map.merge(fields) |> Map.put(:phase, :observing)

          {:noreply,
           socket
           |> put_attempt(attempt)
           |> start_async({:observe, attempt_id}, fn -> observer.(envelope) end)}
        else
          {:noreply, unknown_attempt(socket, attempt_id)}
        end

      _ ->
        {:noreply, socket}
    end
  end

  defp refuse_attempt(socket, attempt_id, reason) do
    socket =
      update_attempt_value(socket, attempt_id, fn attempt ->
        %{attempt | phase: :refused, notice: notice(reason)}
      end)

    {:noreply, push_event(socket, "regents-club-metadata:refused", %{attempt_id: attempt_id})}
  end

  defp unknown_attempt(socket, attempt_id) do
    update_attempt_value(socket, attempt_id, fn attempt ->
      %{attempt | phase: :unknown, notice: notice(:unknown)}
    end)
  end

  defp update_attempt(socket, attempt_id, update) do
    case socket.assigns.attempts[attempt_id] do
      nil -> {:noreply, socket}
      attempt -> {:noreply, put_attempt(socket, update.(attempt))}
    end
  end

  defp update_attempt_value(socket, attempt_id, update) do
    case socket.assigns.attempts[attempt_id] do
      nil -> socket
      attempt -> put_attempt(socket, update.(attempt))
    end
  end

  defp put_attempt(socket, %{id: attempt_id} = attempt) do
    socket
    |> assign(:attempts, Map.put(socket.assigns.attempts, attempt_id, attempt))
    |> stream_insert(:attempts, attempt)
  end

  defp open_app_targets do
    Enum.filter(RouteCatalog.app_targets(), fn
      %{app_id: :autolaunch} -> LaunchGate.autolaunch_surfaces_enabled?()
      _target -> true
    end)
  end

  defp authenticated?(%{principal: {:human, _account}}), do: true
  defp authenticated?(_access_context), do: false

  defp normalized_wallet(address) do
    case Address.normalize(address) do
      {:ok, wallet} -> wallet
      :error -> nil
    end
  end

  defp notice(:finalized),
    do: %{tone: :success, message: "The exact cutover finalized and this route is now closed."}

  defp notice(:reverted),
    do: %{tone: :error, message: "This wallet transaction reverted onchain."}

  defp notice(:cancelled),
    do: %{tone: :info, message: "This wallet request was canceled and will not be retried."}

  defp notice(:unknown),
    do: %{tone: :error, message: "This attempt has an unknown outcome. Review it manually."}

  defp notice(:browser_refused),
    do: %{tone: :error, message: "The selected wallet could not complete this attempt."}

  defp notice(:wallet_changed),
    do: %{tone: :error, message: "The selected Privy wallet changed. Review this attempt again."}

  defp notice(:session_unavailable),
    do: %{tone: :error, message: "The verified session changed. Reload before continuing."}

  defp notice(:readiness_failed),
    do: %{
      tone: :error,
      message: "Representative media or the current Base snapshot did not pass."
    }

  defp notice(:changed_unverified),
    do: %{
      tone: :error,
      message: "The URI changed without exact finalized transaction evidence. Review it manually."
    }

  defp notice(_reason),
    do: %{tone: :error, message: "This attempt could not be prepared. Nothing was sent."}

  defp notice_role(%{tone: :error}), do: "alert"
  defp notice_role(_notice), do: "status"
end
