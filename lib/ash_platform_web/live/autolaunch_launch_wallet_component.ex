defmodule AshPlatformWeb.AutolaunchLaunchWalletComponent do
  @moduledoc """
  One compact card that takes a saved draft through its launch.

  The wallet Privy has selected drives everything here. Its address arrives as
  untrusted browser input and is proved against the mounted lease before any
  private fact is read or any durable write happens, so a wallet this account
  does not hold shows nothing and can neither review nor send.

  The browser reports a hash and stops. Every outcome on screen comes from the
  server's own read of that exact hash, a claimed step is never offered a second
  send, and success here means this server verified its own receipt evidence —
  never that the launch is already published.
  """

  use AshPlatformWeb, :live_component

  alias AshPlatform.Actors.Human
  alias AshPlatform.Autolaunch
  alias AshPlatform.Autolaunch.LaunchActions

  @chain_id 8453

  @copy %{
    authentication_required: "Sign in to launch from your wallet.",
    session_unavailable: "Sign in again to continue.",
    session_lease_required: "Sign in again to continue.",
    wrong_signer: "Switch back to a wallet on this account to continue.",
    invalid_address: "Switch back to a wallet on this account to continue.",
    chain_unavailable: "Base could not be read just now. Try again in a moment.",
    launch_preparation_unavailable: "Launching from your wallet is not open yet.",
    launch_snapshot_incomplete: "Base gave an incomplete answer. Try again in a moment.",
    launches_paused: "New launches are paused right now.",
    insufficient_regent: "This wallet does not hold enough REGENT for the launch fee.",
    recovery_admin_has_no_code:
      "The recovery admin has to be a contract. Change it on this draft and try again.",
    recovery_admin_is_strategy:
      "The recovery admin cannot be the launch strategy. Change it on this draft and try again.",
    required_raise_unreachable:
      "This required raise is higher than an auction can reach. Lower it on this draft and try again.",
    strategy_not_bound:
      "This launch factory and its strategy do not match. Nothing was prepared.",
    launch_metadata_incomplete:
      "This draft is missing something the launch needs. Open it and save every field again.",
    launch_treasury_invalid:
      "This draft's treasury is not a usable address. Copy it from your wallet again and save the draft.",
    launch_recovery_admin_invalid:
      "This draft's recovery admin is not a usable address. Copy it from your wallet again and save the draft.",
    launch_raise_invalid: "This draft's required raise is not a usable amount.",
    launch_draft_not_found: "This draft is no longer available.",
    launch_draft_unavailable: "This draft could not be read just now.",
    launch_in_flight: "Finish or end your open launch before starting another.",
    launch_step_moved: "This launch moved on while you were looking. Check it again.",
    submitted_hash_conflict: "This step already has a transaction.",
    submitted_step_mismatch: "That transaction is not the step this launch is waiting for.",
    launch_operation_not_found: "That launch is no longer open."
  }

  @generic "That did not go through. Try again in a moment."

  # The refusals that mean this browser is not offering a wallet this account
  # holds, so no private fact and no control belongs on screen.
  @unheld [:wrong_signer, :session_unavailable, :session_lease_required, :invalid_address]

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:wallet, fn -> nil end)
     |> assign_new(:notice, fn -> nil end)
     |> assign_new(:operation, fn -> nil end)
     |> assign_new(:elsewhere?, fn -> false end)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section id={@id} class="launch-wallet" phx-hook="AutolaunchLaunchWallet" phx-target={@myself}>
      <.notice :if={@notice} notice={@notice} />

      <p :if={!@authenticated} class="launch-wallet-empty">
        <button type="button" data-account-target="sign-in">Sign in to launch</button>
      </p>

      <div :if={@authenticated && !@wallet} class="launch-wallet-empty">
        <p>Choose the wallet you want to launch from.</p>
        <button type="button" data-launch-wallet-connect>Connect or switch wallet</button>
      </div>

      <p :if={@authenticated && @wallet && @elsewhere?} class="launch-wallet-empty">
        You have a launch in progress on another draft. Finish or end it first.
      </p>

      <div :if={@authenticated && @wallet && !@operation && !@elsewhere?} class="launch-wallet-open">
        <p class="launch-wallet-hint">
          Launching from {short(@wallet)}. Your wallet confirms every step.
        </p>
        <button
          class="launch-wallet-primary"
          type="button"
          phx-click="review_launch"
          phx-target={@myself}
        >
          Review launch
        </button>
      </div>

      <section
        :if={@operation}
        id={"#{@id}-review"}
        class="launch-wallet-review"
        aria-label="Launch review"
      >
        <h4>Review this launch</h4>

        <dl>
          <div>
            <dt>Token</dt>
            <dd>{argument(@operation, "name")} · {argument(@operation, "symbol")}</dd>
          </div>
          <div>
            <dt>Required raise</dt>
            <dd>{argument(@operation, "required_regent_raised")} REGENT</dd>
          </div>
          <div>
            <dt>Launch fee</dt>
            <dd>{fee_display(@operation)}</dd>
          </div>
          <div>
            <dt>Treasury</dt>
            <dd class="launch-wallet-mono">{short(argument(@operation, "treasury"))}</dd>
          </div>
          <div>
            <dt>Recovery admin</dt>
            <dd class="launch-wallet-mono">{short(argument(@operation, "recovery_admin"))}</dd>
          </div>
          <div>
            <dt>Wallet</dt>
            <dd class="launch-wallet-mono">{short(@operation.signer)}</dd>
          </div>
          <div>
            <dt>Network</dt>
            <dd>Base</dd>
          </div>
          <div>
            <dt>Transactions</dt>
            <dd>{step_count(@operation)}</dd>
          </div>
        </dl>

        <p class="launch-wallet-risk">{@operation.envelope["risk_copy"]}</p>

        <ul class="launch-wallet-terms">
          <li :for={sentence <- fixed_terms(@operation)}>{sentence}</li>
        </ul>

        <%!-- The list styling drops list semantics, so the role is stated. --%>
        <ol class="launch-wallet-steps" role="list" aria-label="Launch progress">
          <li :for={step <- LaunchActions.steps(@operation)} data-step={step["step"]}>
            <span>{step_label(step["step"], @operation)}</span>
            <span class="launch-wallet-step-state">{step_state(@operation, step["step"])}</span>
            <.transaction hash={LaunchActions.step_hash(@operation, step["step"])} />
          </li>
        </ol>

        <p :if={@operation.state == :chain_verified} class="launch-wallet-settled" role="status">
          {verified_copy()}
        </p>
        <p
          :if={@operation.state in [:reverted, :unverified]}
          class="launch-wallet-settled"
          role="alert"
        >
          {settled_copy(@operation)}
        </p>
        <p
          :if={
            @operation.state in [:not_sent, :cancelled, :expired, :invalidated, :submission_unknown]
          }
          class="launch-wallet-settled"
          role="status"
        >
          {settled_copy(@operation)}
        </p>

        <details class="launch-wallet-details">
          <summary>Exact values</summary>
          <dl>
            <div :for={{label, value} <- exact_values(@operation)}>
              <dt>{label}</dt>
              <dd class="launch-wallet-mono">{value}</dd>
            </div>
          </dl>
        </details>

        <div class="launch-wallet-controls">
          <button
            :if={sendable?(@operation, @wallet)}
            type="button"
            data-launch-wallet-send={@operation.action_id}
            data-launch-wallet-signer={@operation.signer}
          >
            Confirm in wallet
          </button>
          <p :if={@operation.signer != @wallet && is_nil(@operation.terminal_at)} role="status">
            This launch belongs to another wallet. Switch back to it to finish.
          </p>
          <button
            :if={@operation.state == :submitted}
            type="button"
            phx-click="check_launch_step"
            phx-value-action-id={@operation.action_id}
            phx-target={@myself}
          >
            Check again
          </button>
          <button
            :if={@operation.state == :prepared && !started?(@operation)}
            type="button"
            phx-click="cancel_launch_review"
            phx-value-action-id={@operation.action_id}
            phx-target={@myself}
          >
            Cancel
          </button>
          <button
            :if={@operation.state in [:dispatched, :submitted]}
            type="button"
            phx-click="start_new_launch"
            phx-value-action-id={@operation.action_id}
            phx-target={@myself}
          >
            Start something else
          </button>
          <button
            :if={@operation.terminal_at}
            type="button"
            phx-click="clear_launch"
            phx-target={@myself}
          >
            Done
          </button>
        </div>
      </section>
    </section>
    """
  end

  # The wallet Privy has selected, whenever it changes.
  @impl true
  def handle_event("launch_active_wallet", %{"address" => address}, socket),
    do: {:noreply, adopt(socket, address)}

  def handle_event("review_launch", _params, socket) do
    {:noreply,
     socket.assigns.draft.id
     |> Autolaunch.prepare_launch(socket.assigns.wallet, opts(socket))
     |> settled(socket)}
  end

  # The browser's preflight is necessary input, never authority: the locked
  # dispatch proves the account still holds this wallet and that Base still
  # agrees, and only its winner is handed the exact reviewed bytes.
  def handle_event("sign_launch_step", %{"action-id" => action_id}, socket) do
    action_id
    |> Autolaunch.claim_launch_dispatch(socket.assigns.wallet, opts(socket))
    |> claimed(socket)
  end

  # The bound row goes on screen before Base is asked anything, so a read that
  # cannot answer leaves the transaction and its link exactly where they are.
  def handle_event(
        "launch_submitted",
        %{"action_id" => action_id, "step" => step, "transaction_hash" => hash},
        socket
      ) do
    case wallet_step(step) do
      nil -> {:noreply, socket}
      step -> submitted(socket, action_id, step, hash)
    end
  end

  def handle_event("check_launch_step", %{"action-id" => action_id}, socket),
    do: {:noreply, action_id |> Autolaunch.verify_launch_step(opts(socket)) |> settled(socket)}

  # The exact EIP-1193 rejection of a claimed step: the wallet was asked and said
  # no, so nothing was broadcast and the launch ends. Only that one code ends a
  # launch; any other reported code is not a rejection and changes nothing.
  def handle_event("launch_rejected", %{"action_id" => action_id, "code" => 4001}, socket),
    do: {:noreply, action_id |> Autolaunch.close_launch_not_sent(opts(socket)) |> settled(socket)}

  def handle_event("launch_rejected", _params, socket), do: {:noreply, socket}

  # The browser proved this claimed step never reached its wallet send, so the
  # same review becomes sendable again rather than ending.
  def handle_event("launch_dispatch_not_started", %{"action_id" => action_id}, socket),
    do:
      {:noreply,
       action_id |> Autolaunch.release_unstarted_launch_dispatch(opts(socket)) |> settled(socket)}

  def handle_event("cancel_launch_review", %{"action-id" => action_id}, socket),
    do: {:noreply, action_id |> Autolaunch.cancel_launch_review(opts(socket)) |> settled(socket)}

  def handle_event("start_new_launch", %{"action-id" => action_id}, socket),
    do: {:noreply, action_id |> Autolaunch.start_new_launch(opts(socket)) |> settled(socket)}

  def handle_event("clear_launch", _params, socket),
    do: {:noreply, socket |> assign(operation: nil, notice: nil) |> cleared()}

  # Browser storage only prompts a restore; the owning account's row supplies
  # every fact. No row means the stored hint is stale, and saying so is what
  # stops it asking again on every reload.
  def handle_event("restore_launch_operation", _params, socket) do
    case Autolaunch.open_launch_operation(opts(socket)) do
      {:ok, %{operation: nil}} -> {:noreply, socket |> assign(elsewhere?: false) |> cleared()}
      result -> {:noreply, settled(result, socket)}
    end
  end

  def handle_event("launch_failed", %{"reason" => reason}, socket),
    do: {:noreply, assign(socket, notice: %{tone: :error, message: wallet_failure_copy(reason)})}

  attr :notice, :map, required: true

  defp notice(assigns) do
    ~H"""
    <p class="launch-wallet-notice" role={if @notice.tone == :error, do: "alert", else: "status"}>
      {@notice.message}
    </p>
    """
  end

  attr :hash, :string, default: nil

  defp transaction(assigns) do
    ~H"""
    <a
      :if={@hash}
      class="launch-wallet-mono"
      href={"https://basescan.org/tx/#{@hash}"}
      target="_blank"
      rel="noopener"
      aria-label="View this transaction on Basescan"
    >
      {short_hash(@hash)}
    </a>
    """
  end

  defp submitted(socket, action_id, step, hash) do
    case Autolaunch.bind_launch_hash(action_id, step, hash, opts(socket)) do
      {:ok, %{operation: bound}} = result ->
        socket = settled(result, socket)

        socket =
          action_id
          |> Autolaunch.verify_launch_step(opts(socket))
          |> settled(socket)

        {:noreply, acknowledged(socket, bound, step)}

      refused ->
        {:noreply, settled(refused, socket)}
    end
  end

  # The closed set this card maps a browser value through. Nothing here builds an
  # atom from what the browser sent.
  defp wallet_step("approval"), do: :approval
  defp wallet_step("launch"), do: :launch
  defp wallet_step(_unknown), do: nil

  # One open launch per account, so a row belonging to another draft is named as
  # that rather than shown on this card.
  defp settled({:ok, %{operation: %{launch_draft_id: draft_id} = operation}}, socket) do
    if draft_id == socket.assigns.draft.id do
      socket |> assign(operation: operation, elsewhere?: false, notice: nil) |> published()
    else
      socket |> assign(operation: nil, elsewhere?: true, notice: nil) |> cleared()
    end
  end

  defp settled({:ok, %{operation: nil}}, socket),
    do: socket |> assign(operation: nil, elsewhere?: false) |> cleared()

  defp settled({:error, error}, socket),
    do: assign(socket, notice: notice(:error, refusal(error)))

  # Only the dispatch this claim just won may open a wallet, and it is read from
  # that claim's own result rather than from whatever this socket last held. A
  # refused, invalidated or repeated claim therefore hands the browser nothing.
  defp claimed({:ok, %{operation: %{state: :dispatched} = operation}} = result, socket) do
    {:noreply,
     result
     |> settled(socket)
     |> addressed("autolaunch-launch:send", %{
       action_id: operation.action_id,
       step: Atom.to_string(operation.step)
     })}
  end

  defp claimed(result, socket), do: {:noreply, settled(result, socket)}

  # The one acknowledgement the browser waits for before it drops its own copy of
  # a reported hash: this exact hash is durable on this exact step.
  defp acknowledged(socket, operation, step),
    do:
      addressed(socket, "autolaunch-launch:hash-durable", %{
        action_id: operation.action_id,
        step: Atom.to_string(step),
        transaction_hash: LaunchActions.step_hash(operation, step)
      })

  # The whole reviewed sequence, so the browser can check that what it is asked to
  # send really belongs to the operation it is holding.
  defp published(%{assigns: %{operation: operation}} = socket) do
    addressed(socket, "autolaunch-launch:operation", %{
      action_id: operation.action_id,
      signer: operation.signer,
      chain_id: @chain_id,
      terminal: not is_nil(operation.terminal_at),
      steps: LaunchActions.steps(operation)
    })
  end

  defp cleared(socket), do: addressed(socket, "autolaunch-launch:cleared", %{})

  # A pushed event reaches every hook in the LiveView, and a founder with several
  # saved drafts has one card each. Naming the card the event belongs to is what
  # keeps a dispatch from opening every other card's wallet as well.
  defp addressed(socket, event, payload),
    do: push_event(socket, event, Map.put(payload, :card, socket.assigns.id))

  # No Ethereum wallet selected — disconnected, unlinked, or Solana in front of
  # the customer. That is the ordinary empty state, not a refusal.
  defp adopt(socket, nil), do: assign(socket, wallet: nil, notice: nil)

  defp adopt(socket, address) do
    case Autolaunch.launch_wallet_state(address, opts(socket)) do
      {:ok, %{signer: signer}} -> socket |> assign(wallet: signer, notice: nil) |> restored()
      {:error, error} -> refused(socket, address, refusal(error))
    end
  end

  # The account's open launch is a server fact, so it is read whenever this wallet
  # is adopted. Browser storage only ever prompts a replay of a reported hash; a
  # new tab, another device or cleared storage must still see what is in flight.
  defp restored(%{assigns: %{operation: nil}} = socket) do
    case Autolaunch.open_launch_operation(opts(socket)) do
      {:ok, %{operation: nil}} -> assign(socket, elsewhere?: false)
      {:ok, %{operation: _open}} = result -> settled(result, socket)
      _unavailable -> socket
    end
  end

  defp restored(socket), do: socket

  # Membership is a session fact. A wallet this account does not hold is not
  # adopted at all; one it does hold stays on screen with the reason.
  defp refused(socket, _address, reason) when reason in @unheld,
    do: assign(socket, wallet: nil, notice: notice(:error, reason))

  defp refused(socket, address, reason),
    do: assign(socket, wallet: address, notice: notice(:info, reason))

  defp opts(socket),
    do: [actor: actor(socket), context: %{session_lease: socket.assigns.session_lease}]

  defp actor(%{assigns: %{current_human_id: id}}) when is_integer(id),
    do: %Human{human_account_id: id}

  defp actor(_socket), do: nil

  defp sendable?(%{state: :prepared, signer: signer, terminal_at: nil}, wallet),
    do: signer == wallet

  defp sendable?(_operation, _wallet), do: false

  defp started?(operation),
    do:
      Enum.any?(
        LaunchActions.steps(operation),
        &LaunchActions.step_hash(operation, &1["step"])
      )

  defp step_count(operation) do
    case length(LaunchActions.steps(operation)) do
      1 -> "One transaction"
      2 -> "Two transactions"
    end
  end

  # Where the sequence has got to, read from the operation's own step and state.
  defp step_state(%{step: step} = operation, step_name) do
    cond do
      Atom.to_string(step) == step_name -> current_state(operation.state)
      LaunchActions.step_hash(operation, step_name) -> "Verified"
      true -> "Waiting"
    end
  end

  defp current_state(:prepared), do: "Ready"
  defp current_state(:dispatched), do: "In your wallet"
  defp current_state(:submitted), do: "Sent"
  defp current_state(:chain_verified), do: "Verified"
  defp current_state(:reverted), do: "Reverted"
  defp current_state(:unverified), do: "Unresolved"
  defp current_state(:not_sent), do: "Not sent"
  defp current_state(:cancelled), do: "Cancelled"
  defp current_state(:expired), do: "Expired"
  defp current_state(:invalidated), do: "Out of date"
  defp current_state(:submission_unknown), do: "Unresolved"

  defp step_label("approval", _operation), do: "Allow the launch fee to be taken"
  defp step_label("launch", _operation), do: "Create the launch"

  # The exact customer sentence for a launch this server verified its own
  # evidence for. It deliberately promises no more than that: canonical public
  # confirmation is the finalized projection, not this.
  defp verified_copy,
    do:
      "Your transaction and launch record were verified. This launch will appear here when its onchain record is ready."

  defp settled_copy(%{state: :reverted}),
    do: "This transaction reverted on Base. Nothing was created."

  defp settled_copy(%{state: :unverified}),
    do: "This transaction did not record the launch you reviewed."

  defp settled_copy(%{state: :submission_unknown}),
    do: "This one is still unresolved. Check your wallet activity before you try it again."

  defp settled_copy(%{state: :not_sent} = operation),
    do: "Your wallet declined this." <> left_behind(operation)

  defp settled_copy(%{state: :cancelled} = operation),
    do: "This review was cancelled." <> left_behind(operation)

  defp settled_copy(%{state: :expired} = operation),
    do: "This review expired before the launch was sent." <> left_behind(operation)

  defp settled_copy(%{state: :invalidated} = operation),
    do:
      "Base moved on before the launch was sent." <>
        left_behind(operation) <> ended_because(operation)

  # A review that ends after its allowance correction was already sent leaves
  # that exact allowance standing on Base, so claiming nothing was sent would be
  # false. The standing approval is named instead, and the next review's
  # exact-equality branch is what corrects it.
  defp left_behind(operation) do
    if LaunchActions.step_hash(operation, "approval"),
      do:
        " Your REGENT approval was already sent, so that allowance may still be active. A fresh review corrects that allowance exactly.",
      else: " Nothing was sent."
  end

  defp ended_because(%{reason: reason}) when is_binary(reason),
    do: " Review it again: #{reason}."

  defp ended_because(_operation), do: ""

  # The founder-frozen terms, in the order a founder meets them. Nobody chooses
  # any of them, so they are stated rather than offered, and the exact start block
  # is never inferred: only the fixed delay is promised.
  defp fixed_terms(operation) do
    terms = argument(operation, "terms")

    [
      "Bidding opens a fixed delay after your launch transaction is mined, then runs for a fixed number of blocks.",
      "Claiming opens a short fixed delay after bidding closes, and moving to a pool opens a little after that.",
      "#{share(terms, "auction_allocation")} of the supply is sold in the auction, #{share(terms, "reserve_allocation")} is kept as the pool reserve, and #{share(terms, "pending_allocation")} stays in escrow until the launch settles.",
      "The pool fee is #{pool_fee(terms)}.",
      "Every launch uses these same terms. Nothing here is chosen by you or by us."
    ]
  end

  # The three allocations are the whole supply, so each share is read from the
  # reviewed terms rather than restated as a literal here.
  defp share(terms, key) do
    total =
      Enum.sum(
        Enum.map(~w(auction_allocation reserve_allocation pending_allocation), &number(terms, &1))
      )

    "#{div(number(terms, key) * 100, total)}%"
  end

  # Uniswap states a static pool fee in hundredths of a basis point.
  defp pool_fee(terms),
    do: "#{:erlang.float_to_binary(number(terms, "pool_fee") / 10_000, decimals: 2)}%"

  defp number(terms, key), do: terms |> Map.fetch!(key) |> String.to_integer()

  # Everything technical, behind the one disclosure: raw addresses, the exact
  # target, the reviewed block, the Q96 values, the block counts and the digest
  # of the exact bytes this wallet is being asked to sign.
  defp exact_values(operation) do
    terms = argument(operation, "terms")

    [
      {"Factory", argument(operation, "factory")},
      {"Strategy", argument(operation, "strategy")},
      {"Treasury", argument(operation, "treasury")},
      {"Recovery admin", argument(operation, "recovery_admin")},
      {"Required raise (atomic)", argument(operation, "required_regent_raised_atomic")},
      {"Launch fee (atomic)", argument(operation, "expected_launch_fee_atomic")},
      {"Reviewed block",
       "#{argument(operation, "block_number")} · #{argument(operation, "block_hash")}"},
      {"Calldata digest", operation.envelope["metadata"]["calldata_sha256"]}
    ] ++ Enum.map(LaunchActions.terms(), &{term_label(&1), Map.fetch!(terms, &1)})
  end

  defp term_label(key), do: key |> String.replace("_", " ") |> String.capitalize()

  defp fee_display(operation) do
    case argument(operation, "expected_launch_fee") do
      "0" -> "None right now"
      fee -> "#{fee} REGENT"
    end
  end

  # The browser reports a closed reason key as a string, never text of its own.
  # Only a key that proves the wallet was never asked to send may say nothing was
  # sent; everything else leaves the question open and says so.
  defp wallet_failure_copy("wallet_unavailable"),
    do: "Open the wallet you are using here, then try again. Nothing was sent."

  defp wallet_failure_copy("send_unconfirmed"),
    do:
      "Your wallet may have sent this transaction. Check your wallet activity before you start another launch."

  defp wallet_failure_copy(_unknown), do: @generic

  defp notice(tone, reason), do: %{tone: tone, message: Map.get(@copy, reason, @generic)}

  defp refusal(%{errors: errors}), do: Enum.find_value(errors, :unavailable, &unavailable/1)
  defp refusal(%Ash.Error.Invalid.Unavailable{reason: reason}), do: reason
  defp refusal(reason) when is_atom(reason), do: reason
  defp refusal(_other), do: :unavailable

  defp unavailable(%Ash.Error.Invalid.Unavailable{reason: reason}), do: reason
  defp unavailable(_other), do: nil

  defp argument(%{envelope: envelope}, key), do: envelope["arguments"][key]

  defp short("0x" <> address),
    do: "0x#{String.slice(address, 0, 4)}…#{String.slice(address, -4, 4)}"

  defp short_hash("0x" <> hash),
    do: "0x#{String.slice(hash, 0, 6)}…#{String.slice(hash, -4, 4)}"
end
