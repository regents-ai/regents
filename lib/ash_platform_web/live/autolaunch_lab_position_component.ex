defmodule AshPlatformWeb.AutolaunchLabPositionComponent do
  @moduledoc false

  use AshPlatformWeb, :live_component

  alias AshPlatform.Actors.Human
  alias AshPlatform.Autolaunch

  @copy %{
    authentication_required: "Sign in to manage this local test position.",
    session_unavailable: "Sign in again to continue.",
    wrong_signer: "Switch back to the wallet that owns this bid.",
    invalid_address: "Choose an Ethereum wallet on this account.",
    multiple_lab_positions: "This page supports one exact local test bid at a time.",
    lab_position_not_found: "This wallet has no projected bid on this auction.",
    lab_launch_not_found: "The local launch record is unavailable.",
    lab_position_mismatch: "The local bid no longer matches its projected launch.",
    lab_position_changed: "The local bid changed. Review it again.",
    lab_config_changed: "The local lab changed. Review this action again.",
    lab_contract_missing: "The local lab is no longer running.",
    auction_not_finished: "The local auction has not ended yet.",
    bid_already_exited: "This bid has already exited.",
    partial_fill_unsupported: "This partially filled bid is outside the local test flow.",
    claim_not_open: "Token claiming is not open yet.",
    auction_not_graduated: "This auction did not graduate.",
    bid_not_exited: "Exit this bid before claiming its tokens.",
    nothing_to_claim: "This bid has no unclaimed tokens.",
    migration_not_available: "This launch has already reached its terminal state.",
    migration_not_open: "Migration is not open yet.",
    chain_unavailable: "The local lab could not be read. Check that it is still running.",
    invalid_chain_response: "The local lab returned an incomplete answer.",
    transaction_pending: "The local transaction is still pending."
  }

  @generic "That local test action did not go through. Try again."

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:wallet, fn -> nil end)
     |> assign_new(:position, fn -> nil end)
     |> assign_new(:operation, fn -> nil end)
     |> assign_new(:notice, fn -> nil end)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section
      id={@id}
      class="autolaunch-lab-position bid-panel"
      phx-hook="AutolaunchLabPosition"
      phx-target={@myself}
      aria-labelledby={"#{@id}-title"}
    >
      <p class="autolaunch-kicker">Local Base fork · test assets · no mainnet value</p>
      <h3 id={"#{@id}-title"}>Local test position</h3>
      <p
        :if={@notice}
        class="bid-notice"
        role={if @notice.tone == :error, do: "alert", else: "status"}
      >
        {@notice.message}
      </p>

      <p :if={!@authenticated} class="autolaunch-empty">
        Sign in to manage the exact bid created in this local lab.
      </p>

      <div :if={@authenticated && !@wallet} class="autolaunch-empty">
        <p>Choose the wallet that placed the local test bid.</p>
        <button type="button" data-lab-position-connect>Connect or switch wallet</button>
      </div>

      <p :if={@authenticated && @wallet && is_nil(@position)} class="autolaunch-empty">
        This wallet has no projected bid on this auction yet.
      </p>

      <div
        :if={@position && is_nil(@operation)}
        class="autolaunch-lab-position-actions launch-wallet-review"
      >
        <dl>
          <div>
            <dt>Wallet</dt><dd class="bid-mono">{short(@wallet)}</dd>
          </div>
          <div>
            <dt>Bid</dt><dd>{@position.bid.onchain_bid_id}</dd>
          </div>
          <div>
            <dt>Local block</dt><dd>{@position.current_block}</dd>
          </div>
          <div>
            <dt>Status</dt><dd>{status_label(@position.status)}</dd>
          </div>
        </dl>
        <div class="launch-wallet-controls">
          <button
            :if={@position.actions.exit}
            type="button"
            data-lab-position-prepare="exit"
          >
            Exit full bid
          </button>
          <button
            :if={@position.actions.claim}
            type="button"
            data-lab-position-prepare="claim"
          >
            Claim local tokens
          </button>
          <button
            :if={@position.actions.migrate}
            type="button"
            data-lab-position-prepare="migrate"
          >
            Run permissionless migration
          </button>
        </div>
      </div>

      <section :if={@operation} class="launch-wallet-review" aria-label="Local test action review">
        <h4>{kind_label(@operation.kind)}</h4>
        <dl>
          <div>
            <dt>Network</dt><dd>Local Base fork · chain 31337</dd>
          </div>
          <div>
            <dt>Wallet</dt><dd class="bid-mono">{short(@operation.signer)}</dd>
          </div>
          <div>
            <dt>Target</dt><dd class="bid-mono">{short(step(@operation)["to"])}</dd>
          </div>
          <div>
            <dt>State</dt><dd>{state_label(@operation.state)}</dd>
          </div>
        </dl>
        <p class="launch-wallet-risk">{@operation.envelope["risk_copy"]}</p>
        <p :if={@operation.transaction_hash} class="bid-mono" data-local-transaction-hash>
          {short_hash(@operation.transaction_hash)}
        </p>
        <div class="launch-wallet-controls">
          <button
            :if={@operation.state == :prepared && @operation.signer == @wallet}
            type="button"
            data-lab-position-send={@operation.action_id}
            data-lab-position-signer={@operation.signer}
          >
            Confirm in wallet
          </button>
          <button
            :if={@operation.state == :submitted}
            type="button"
            data-lab-position-verify={@operation.action_id}
          >
            Check again
          </button>
          <button
            :if={@operation.state == :prepared}
            type="button"
            data-lab-position-cancel={@operation.action_id}
          >
            Cancel
          </button>
          <button
            :if={@operation.state in [:confirmed, :reverted, :unverified, :not_sent]}
            type="button"
            data-lab-position-start-new={@operation.action_id}
          >
            Done
          </button>
        </div>
      </section>
    </section>
    """
  end

  @impl true
  def handle_event("lab_position_active_wallet", %{"address" => nil}, socket),
    do: {:noreply, assign(socket, wallet: nil, position: nil, operation: nil, notice: nil)}

  def handle_event("lab_position_active_wallet", %{"address" => address}, socket) do
    case Autolaunch.lab_position(socket.assigns.auction.id, address, opts(socket)) do
      {:ok, %{bid: nil, signer: signer}} ->
        {:noreply, assign(socket, wallet: signer, position: nil, operation: nil, notice: nil)}

      {:ok, %{signer: signer} = position} ->
        {:noreply,
         assign(socket, wallet: signer, position: position, operation: nil, notice: nil)}

      {:error, reason} ->
        {:noreply,
         assign(socket, wallet: nil, position: nil, operation: nil, notice: error(reason))}
    end
  end

  def handle_event(
        "prepare_lab_position",
        %{"address" => address, "kind" => kind},
        %{assigns: %{position: %{bid: bid}}} = socket
      ) do
    with {:ok, kind} <- kind(kind),
         {:ok, %{operation: operation}} <-
           Autolaunch.prepare_lab_position(bid.bid_id, address, kind, opts(socket)) do
      {:noreply, socket |> assign(operation: operation, notice: nil) |> published()}
    else
      {:error, reason} -> {:noreply, assign(socket, notice: error(reason))}
    end
  end

  def handle_event("prepare_lab_position", _params, socket),
    do: {:noreply, assign(socket, notice: error(:lab_position_not_found))}

  def handle_event(
        "sign_lab_position_step",
        %{"action-id" => action_id},
        %{assigns: %{operation: %{action_id: action_id} = operation}} = socket
      ) do
    case Autolaunch.claim_lab_position_dispatch(operation, socket.assigns.wallet, opts(socket)) do
      {:ok, %{operation: claimed}} ->
        {:noreply,
         socket
         |> assign(operation: claimed, notice: nil)
         |> published()
         |> push_event("autolaunch-lab-position:send", %{
           action_id: claimed.action_id,
           step: Atom.to_string(claimed.kind)
         })}

      {:error, reason} ->
        {:noreply, assign(socket, notice: error(reason))}
    end
  end

  def handle_event(
        "lab_position_submitted",
        %{"action_id" => action_id, "step" => step_name, "transaction_hash" => hash},
        %{assigns: %{operation: %{action_id: action_id} = operation}} = socket
      ) do
    if step_name == Atom.to_string(operation.kind) do
      submitted = %{operation | state: :submitted, transaction_hash: hash}
      {:noreply, socket |> assign(operation: submitted, notice: nil) |> verify(submitted, hash)}
    else
      {:noreply, socket}
    end
  end

  def handle_event(
        "lab_position_verify",
        %{"action-id" => action_id},
        %{assigns: %{operation: %{action_id: action_id, transaction_hash: hash} = operation}} =
          socket
      )
      when is_binary(hash),
      do: {:noreply, verify(socket, operation, hash)}

  def handle_event(
        "lab_position_dispatch_not_started",
        %{"action_id" => action_id},
        %{assigns: %{operation: %{action_id: action_id} = operation}} = socket
      ),
      do: {:noreply, socket |> assign(operation: %{operation | state: :prepared}) |> published()}

  def handle_event(
        "lab_position_rejected",
        %{"action_id" => action_id, "code" => 4001},
        %{assigns: %{operation: %{action_id: action_id} = operation}} = socket
      ),
      do:
        {:noreply,
         socket
         |> assign(
           operation: %{operation | state: :not_sent, terminal_at: DateTime.utc_now()},
           notice: %{tone: :info, message: "Your wallet declined this local test transaction."}
         )
         |> published()}

  def handle_event("cancel_lab_position", _params, socket), do: {:noreply, cleared(socket)}
  def handle_event("start_new_lab_position", _params, socket), do: {:noreply, cleared(socket)}
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp verify(socket, operation, hash) do
    case Autolaunch.verify_lab_position(operation, hash, opts(socket)) do
      {:ok, %{operation: verified}} ->
        socket
        |> assign(operation: verified, notice: success_notice(verified))
        |> published()

      {:error, reason} ->
        assign(socket, notice: error(reason))
    end
  end

  defp published(%{assigns: %{operation: operation}} = socket) do
    push_event(socket, "autolaunch-lab-position:operation", %{
      action_id: operation.action_id,
      signer: operation.signer,
      chain_id: operation.envelope["chain_id"],
      lab: operation.envelope["metadata"]["lab"],
      lab_anchor: %{
        block_number: operation.envelope["arguments"]["reviewed_block_number"],
        block_hash: operation.envelope["arguments"]["reviewed_block_hash"]
      },
      terminal: not is_nil(operation.terminal_at),
      steps: operation.envelope["arguments"]["steps"]
    })
  end

  defp cleared(socket) do
    socket
    |> assign(operation: nil, notice: nil)
    |> push_event("autolaunch-lab-position:cleared", %{})
  end

  defp success_notice(%{state: :confirmed}),
    do: %{tone: :info, message: "The local transaction and its chain result were verified."}

  defp success_notice(%{state: :reverted}),
    do: %{tone: :error, message: "This local transaction reverted."}

  defp success_notice(%{state: :unverified}),
    do: %{tone: :error, message: "This local receipt did not match the reviewed action."}

  defp success_notice(%{state: :submitted}),
    do: %{tone: :info, message: "The local transaction is still pending."}

  defp success_notice(_operation), do: nil

  defp opts(socket),
    do: [actor: actor(socket), context: %{session_lease: socket.assigns.session_lease}]

  defp actor(%{assigns: %{current_human_id: id}}) when is_integer(id),
    do: %Human{human_account_id: id}

  defp actor(_socket), do: nil

  defp kind("exit"), do: {:ok, :exit}
  defp kind("claim"), do: {:ok, :claim}
  defp kind("migrate"), do: {:ok, :migrate}
  defp kind(_unknown), do: {:error, :unknown_lab_position_action}

  defp error(reason), do: %{tone: :error, message: Map.get(@copy, refusal(reason), @generic)}
  defp refusal(%Ash.Error.Invalid.Unavailable{reason: reason}), do: reason
  defp refusal(%{errors: errors}), do: Enum.find_value(errors, :unavailable, &refusal/1)
  defp refusal(reason) when is_atom(reason), do: reason
  defp refusal(_other), do: :unavailable

  defp step(operation), do: operation.envelope["arguments"]["steps"] |> List.first()

  defp kind_label(:exit), do: "Exit this full bid"
  defp kind_label(:claim), do: "Claim local test tokens"
  defp kind_label(:migrate), do: "Migrate this local launch"

  defp status_label(:countdown), do: "Countdown"
  defp status_label(:auction), do: "Auction running"
  defp status_label(:exit_ready), do: "Ready to exit"
  defp status_label(:claim_ready), do: "Ready to claim"
  defp status_label(:migration_ready), do: "Ready to migrate"
  defp status_label(:terminal), do: "Terminal"
  defp status_label(_status), do: "Waiting"

  defp state_label(:prepared), do: "Ready"
  defp state_label(:dispatched), do: "In your wallet"
  defp state_label(:submitted), do: "Sent"
  defp state_label(:confirmed), do: "Verified"
  defp state_label(:reverted), do: "Reverted"
  defp state_label(:unverified), do: "Unresolved"
  defp state_label(:not_sent), do: "Not sent"

  defp short("0x" <> address),
    do: "0x#{String.slice(address, 0, 4)}…#{String.slice(address, -4, 4)}"

  defp short(value), do: value

  defp short_hash("0x" <> hash),
    do: "0x#{String.slice(hash, 0, 6)}…#{String.slice(hash, -4, 4)}"
end
