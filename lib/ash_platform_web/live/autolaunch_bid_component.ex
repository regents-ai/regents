defmodule AshPlatformWeb.AutolaunchBidComponent do
  @moduledoc """
  The whole bidder: one compact form, one review, and the transactions it needs.

  The wallet Privy has selected drives everything here. Its address arrives as
  untrusted browser input and is proved against the mounted lease before any
  private fact is read or any durable write happens, so a wallet this account
  does not hold shows a balance of nothing and can neither review nor send.

  The browser reports a hash and stops. Every outcome on screen comes from the
  server's own read of that exact hash, and a claimed step is never offered a
  second send.
  """

  use AshPlatformWeb, :live_component

  alias AshPlatform.Actors.Human
  alias AshPlatform.Autolaunch
  alias AshPlatform.Autolaunch.BidActions

  @chain_id 8453

  @copy %{
    bid_preparation_unavailable: "Bidding is not open on this auction yet.",
    chain_unavailable: "Base could not be read just now. Nothing was sent.",
    wrong_signer: "Switch back to a wallet on this account to continue.",
    session_unavailable: "Sign in again to continue.",
    auction_not_biddable: "This auction is not taking bids.",
    auction_currency_is_not_regent: "This auction does not take REGENT.",
    amount_above_balance: "That is more REGENT than this wallet holds.",
    bid_in_flight: "Finish or end your open bid before starting another.",
    invalid_amount: "Enter a REGENT amount with up to eighteen decimal places.",
    invalid_price: "Enter a maximum price above zero.",
    invalid_decimal: "Enter a maximum price above zero.",
    submitted_hash_conflict: "This step already has a transaction.",
    wallet_unavailable: "Open the wallet you are bidding from, then try again."
  }

  @generic "That did not go through. Nothing was sent."

  # The refusals that mean this browser is not offering a wallet this account
  # holds, so no private fact and no control belongs on screen.
  @unheld [:wrong_signer, :session_unavailable, :session_lease_required, :invalid_address]

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:wallet, fn -> nil end)
     |> assign_new(:balance, fn -> nil end)
     |> assign_new(:amount, fn -> "" end)
     |> assign_new(:max_price, fn -> "" end)
     |> assign_new(:estimate, fn -> nil end)
     |> assign_new(:notice, fn -> nil end)
     |> assign_new(:signing?, fn -> false end)
     |> assign_new(:operation, fn -> nil end)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section id={@id} class="bid-panel" phx-hook="AutolaunchBidWallet" phx-target={@myself}>
      <header class="bid-heading">
        <h2>Place a bid</h2>
        <p>Bid REGENT for this launch. Your wallet confirms every step.</p>
      </header>

      <.notice :if={@notice} notice={@notice} />

      <p :if={!@authenticated} class="bid-empty">
        <button type="button" data-account-target="sign-in">Sign in to bid</button>
      </p>

      <div :if={@authenticated && !@wallet} class="bid-empty">
        <p>Choose the wallet you want to bid from.</p>
        <button type="button" data-bid-connect>Connect or switch wallet</button>
      </div>

      <div :if={@authenticated && @wallet} class="bid-body">
        <dl class="bid-wallet">
          <div>
            <dt>Wallet</dt><dd class="bid-mono">{short(@wallet)}</dd>
          </div>
          <div>
            <dt>REGENT</dt><dd>{balance(@balance)}</dd>
          </div>
        </dl>

        <form
          :if={!@operation}
          id={"#{@id}-form"}
          phx-change="bid_form_changed"
          phx-submit="review_bid"
          phx-target={@myself}
        >
          <label for={"#{@id}-amount"}>Amount</label>
          <div class="bid-amount">
            <input
              id={"#{@id}-amount"}
              name="amount"
              value={@amount}
              inputmode="decimal"
              autocomplete="off"
              placeholder="0.0"
            />
            <button
              type="button"
              phx-click="fill_bid_amount"
              phx-target={@myself}
              disabled={is_nil(@balance)}
            >
              Max
            </button>
          </div>

          <label for={"#{@id}-max-price"}>Maximum price</label>
          <input
            id={"#{@id}-max-price"}
            name="max_price"
            value={@max_price}
            inputmode="decimal"
            autocomplete="off"
            placeholder="0.0"
          />

          <p :if={@estimate} class="bid-estimate">
            You would receive about {@estimate} tokens if the auction ended now.
          </p>

          <button class="bid-primary" type="submit" disabled={@amount == "" or @max_price == ""}>
            Review bid
          </button>
        </form>

        <section :if={@operation} id={"#{@id}-review"} class="bid-review" aria-label="Bid review">
          <dl>
            <div>
              <dt>Amount</dt><dd>{argument(@operation, "amount")} REGENT</dd>
            </div>
            <div>
              <dt>Maximum price</dt><dd>{argument(@operation, "max_price")}</dd>
            </div>
            <div>
              <dt>Network</dt><dd>Base</dd>
            </div>
          </dl>

          <ol class="bid-steps">
            <li :for={step <- BidActions.steps(@operation)} data-step={step["step"]}>
              <span>{step_label(step["step"])}</span>
              <span class="bid-step-state">{step_state(@operation, step["step"])}</span>
              <.transaction hash={BidActions.step_hash(@operation, step["step"])} />
            </li>
          </ol>

          <p :if={@operation.state == :confirmed} class="bid-settled" role="status">
            Bid {@operation.onchain_bid_id} is on Base. Your position appears once it is read back.
          </p>
          <p :if={@operation.state in [:reverted, :unverified]} class="bid-settled" role="alert">
            {settled_copy(@operation.state)}
          </p>

          <button
            :if={sendable?(@operation, @wallet)}
            type="button"
            data-bid-send={@operation.action_id}
            data-bid-signer={@operation.signer}
            disabled={@signing?}
          >
            {if @signing?, do: "Waiting for wallet", else: "Confirm in wallet"}
          </button>
          <p :if={@operation.signer != @wallet && is_nil(@operation.terminal_at)} role="status">
            This bid belongs to another wallet. Switch back to it to finish.
          </p>
          <button
            :if={@operation.state == :submitted}
            type="button"
            phx-click="check_bid_step"
            phx-value-action-id={@operation.action_id}
            phx-target={@myself}
          >
            Check again
          </button>
          <button
            :if={@operation.state == :prepared && !started?(@operation)}
            type="button"
            phx-click="cancel_bid_review"
            phx-value-action-id={@operation.action_id}
            phx-target={@myself}
          >
            Cancel
          </button>
          <button
            :if={@operation.state in [:dispatched, :submitted]}
            type="button"
            phx-click="start_new_bid"
            phx-value-action-id={@operation.action_id}
            phx-target={@myself}
          >
            Start a new bid
          </button>
          <button
            :if={@operation.terminal_at}
            type="button"
            phx-click="clear_bid"
            phx-target={@myself}
          >
            Place another bid
          </button>
        </section>
      </div>
    </section>
    """
  end

  # The wallet Privy has selected. A change abandons an undispatched review's
  # form state and rereads the position; an operation already claimed stays on
  # screen bound to the signer it was reviewed for.
  @impl true
  def handle_event("bid_active_wallet", %{"address" => address}, socket),
    do: {:noreply, adopt(socket, address)}

  def handle_event("bid_form_changed", %{"amount" => amount, "max_price" => max_price}, socket) do
    {:noreply,
     socket |> assign(amount: amount, max_price: max_price, notice: nil) |> assign_estimate()}
  end

  def handle_event("fill_bid_amount", _params, %{assigns: %{balance: nil}} = socket),
    do: {:noreply, socket}

  def handle_event("fill_bid_amount", _params, socket) do
    {:noreply,
     socket
     |> assign(amount: balance(socket.assigns.balance), notice: nil)
     |> assign_estimate()}
  end

  def handle_event("review_bid", %{"amount" => amount, "max_price" => max_price}, socket) do
    socket.assigns.auction.id
    |> Autolaunch.prepare_bid(socket.assigns.wallet, amount, max_price, opts(socket))
    |> settled(assign(socket, amount: amount, max_price: max_price))
  end

  # The browser's preflight is necessary input, never authority: the locked
  # dispatch proves the account still holds this wallet, and only its winner is
  # handed the exact reviewed bytes.
  def handle_event("sign_bid_step", %{"action-id" => action_id, "address" => address}, socket) do
    if socket.assigns.signing? or address != socket.assigns.wallet do
      {:noreply, socket}
    else
      action_id
      |> Autolaunch.claim_bid_dispatch(opts(socket))
      |> settled(assign(socket, signing?: true))
      |> dispatch()
    end
  end

  def handle_event(
        "bid_submitted",
        %{"action_id" => action_id, "transaction_hash" => hash},
        socket
      ) do
    case Autolaunch.bind_bid_hash(action_id, hash, opts(socket)) do
      {:ok, _bound} -> action_id |> Autolaunch.verify_bid_step(opts(socket)) |> settled(socket)
      refused -> settled(refused, socket)
    end
  end

  def handle_event("check_bid_step", %{"action-id" => action_id}, socket),
    do: action_id |> Autolaunch.verify_bid_step(opts(socket)) |> settled(socket)

  # The exact EIP-1193 rejection of a claimed step: the wallet was asked and
  # said no, so nothing was broadcast and the operation ends.
  def handle_event("bid_wallet_rejected", %{"action_id" => action_id, "code" => 4001}, socket),
    do: action_id |> Autolaunch.close_bid_not_sent(opts(socket)) |> settled(socket)

  # The browser proved this claimed step never reached its wallet send, so the
  # same review becomes sendable again rather than ending.
  def handle_event("bid_dispatch_not_started", %{"action_id" => action_id}, socket),
    do: action_id |> Autolaunch.release_unstarted_bid_dispatch(opts(socket)) |> settled(socket)

  def handle_event("cancel_bid_review", %{"action-id" => action_id}, socket),
    do: action_id |> Autolaunch.cancel_bid_review(opts(socket)) |> settled(socket)

  def handle_event("start_new_bid", %{"action-id" => action_id}, socket),
    do: action_id |> Autolaunch.start_new_bid(opts(socket)) |> settled(socket)

  def handle_event("clear_bid", _params, socket),
    do:
      {:noreply,
       socket |> assign(operation: nil, amount: "", max_price: "", estimate: nil) |> cleared()}

  # Browser storage only prompts a restore; the owning account's row supplies
  # every fact. No row means the stored hint is stale, and saying so is what
  # stops it asking again on every reload.
  def handle_event("restore_bid_operation", _params, socket) do
    case Autolaunch.open_bid_operation(opts(socket)) do
      {:ok, %{operation: nil}} -> {:noreply, cleared(socket)}
      result -> settled(result, socket)
    end
  end

  def handle_event("bid_wallet_failed", %{"reason" => reason}, socket),
    do: {:noreply, assign(socket, signing?: false, notice: notice(:error, reason))}

  attr :notice, :map, required: true

  defp notice(assigns) do
    ~H"""
    <p class="bid-notice" role={if @notice.tone == :error, do: "alert", else: "status"}>
      {@notice.message}
    </p>
    """
  end

  attr :hash, :string, default: nil

  defp transaction(assigns) do
    ~H"""
    <a
      :if={@hash}
      class="bid-mono"
      href={"https://basescan.org/tx/#{@hash}"}
      target="_blank"
      rel="noopener"
    >
      {short_hash(@hash)}
    </a>
    """
  end

  defp settled({:ok, %{operation: operation}}, socket),
    do:
      {:noreply,
       socket |> assign(operation: operation, signing?: false, notice: nil) |> published()}

  defp settled({:error, error}, socket),
    do: {:noreply, assign(socket, signing?: false, notice: notice(:error, refusal(error)))}

  # Only the dispatch this socket just won may open a wallet, and it is named by
  # step alone: the bytes the browser signs are the ones it was already given.
  defp dispatch({:noreply, %{assigns: %{operation: %{state: :dispatched} = operation}} = socket}) do
    {:noreply,
     push_event(socket, "autolaunch-bid:send", %{
       action_id: operation.action_id,
       step: Atom.to_string(operation.step)
     })}
  end

  defp dispatch(result), do: result

  # The whole reviewed sequence, so the browser can check that what it is asked
  # to send really belongs to the operation it is holding.
  defp published(%{assigns: %{operation: nil}} = socket), do: cleared(socket)

  defp published(%{assigns: %{operation: operation}} = socket) do
    push_event(socket, "autolaunch-bid:operation", %{
      action_id: operation.action_id,
      signer: operation.signer,
      chain_id: @chain_id,
      terminal: not is_nil(operation.terminal_at),
      steps: BidActions.steps(operation)
    })
  end

  defp cleared(socket), do: push_event(socket, "autolaunch-bid:cleared", %{})

  defp adopt(socket, address) do
    case Autolaunch.bid_position(socket.assigns.auction.id, address, opts(socket)) do
      {:ok, %{signer: signer, balance: balance}} ->
        assign(socket, wallet: signer, balance: balance, notice: nil)

      {:error, error} ->
        refused(socket, address, refusal(error))
    end
  end

  # Membership is a session fact and a balance is a chain fact. A wallet this
  # account does not hold is not adopted at all; one it does hold stays on
  # screen with the reason its position could not be read.
  defp refused(socket, _address, reason) when reason in @unheld,
    do: assign(socket, wallet: nil, balance: nil, notice: notice(:error, reason))

  defp refused(socket, address, reason),
    do: assign(socket, wallet: address, balance: nil, notice: notice(:info, reason))

  defp assign_estimate(%{assigns: %{amount: amount, max_price: max_price}} = socket) do
    case Autolaunch.quote_auction_bid(socket.assigns.auction.id, amount, max_price) do
      {:ok, %{estimated_tokens_if_end_now: estimate}} -> assign(socket, estimate: estimate)
      {:error, _incomplete} -> assign(socket, estimate: nil)
    end
  end

  defp opts(socket),
    do: [
      actor: actor(socket),
      context: %{session_lease: socket.assigns.session_lease}
    ]

  defp actor(%{assigns: %{current_human_id: id}}) when is_integer(id),
    do: %Human{human_account_id: id}

  defp actor(_socket), do: nil

  defp sendable?(%{state: :prepared, signer: signer, terminal_at: nil}, wallet),
    do: signer == wallet

  defp sendable?(_operation, _wallet), do: false

  defp started?(operation),
    do: Enum.any?(BidActions.steps(operation), &BidActions.step_hash(operation, &1["step"]))

  # Where the sequence has got to, read from the operation's own step and state.
  defp step_state(%{step: step} = operation, step_name) do
    cond do
      Atom.to_string(step) == step_name -> current_state(operation.state)
      BidActions.step_hash(operation, step_name) -> "Confirmed"
      true -> "Waiting"
    end
  end

  defp current_state(:prepared), do: "Ready"
  defp current_state(:dispatched), do: "In your wallet"
  defp current_state(:submitted), do: "Sent"
  defp current_state(:confirmed), do: "Confirmed"
  defp current_state(:reverted), do: "Reverted"
  defp current_state(:unverified), do: "Unresolved"
  defp current_state(:not_sent), do: "Not sent"
  defp current_state(:cancelled), do: "Cancelled"
  defp current_state(:expired), do: "Expired"
  defp current_state(:submission_unknown), do: "Unresolved"

  defp step_label("token_approval"), do: "Allow REGENT to be spent"
  defp step_label("permit2_approval"), do: "Allow this auction to draw REGENT"
  defp step_label("bid"), do: "Place the bid"

  defp settled_copy(:reverted), do: "This transaction reverted on Base."
  defp settled_copy(:unverified), do: "This transaction did not record the bid you reviewed."

  defp notice(tone, reason), do: %{tone: tone, message: Map.get(@copy, reason, @generic)}

  defp refusal(%{errors: errors}), do: Enum.find_value(errors, :unavailable, &unavailable/1)
  defp refusal(reason) when is_atom(reason), do: reason
  defp refusal(_other), do: :unavailable

  defp unavailable(%Ash.Error.Invalid.Unavailable{reason: reason}), do: reason
  defp unavailable(_other), do: nil

  defp argument(%{envelope: envelope}, key), do: envelope["arguments"][key]

  defp balance(nil), do: "—"
  defp balance(atomic), do: atomic |> String.to_integer() |> Autolaunch.bid_amount_units()

  defp short("0x" <> address),
    do: "0x#{String.slice(address, 0, 4)}…#{String.slice(address, -4, 4)}"

  defp short_hash("0x" <> hash),
    do: "0x#{String.slice(hash, 0, 6)}…#{String.slice(hash, -4, 4)}"
end
