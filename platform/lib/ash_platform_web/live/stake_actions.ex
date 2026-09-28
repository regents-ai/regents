defmodule AshPlatformWeb.StakeActions do
  @moduledoc """
  The Stake page's actions: the amount form, the wallet buttons and what
  happened to each press.

  Every step is built on the server and pushed to the page before anyone
  presses; the browser sends only what the review holds and reports what the
  wallet said. `skills/onchain-buttons` has the rules and
  `AshPlatformWeb.OnchainSteps` the shared half.

  The page passes the readings (`staking`, for `wallet`) and `linked`, the
  signed-in account's wallets (`nil` signed out). Only Privy's active wallet
  acts, and only when the account links it. The component tells the page which
  wallet Privy has active, so the figures follow it, and when a step lands, so
  they are read again.
  """
  use AshPlatformWeb, :live_component

  alias AshPlatform.{ChainClient, Staking}
  alias AshPlatform.Staking.{SnapshotCache, Steps}
  alias AshPlatformWeb.Components.Loading
  alias AshPlatformWeb.{EventInput, OnchainSteps, StakeLive, TokenDisplay}
  alias Phoenix.LiveView.JS
  alias RegentChain.{Presses, Review}

  import AshPlatformWeb.EventInput, only: [failure_reason: 1]

  @blank_form %{for_other: false, receiver: "", acknowledged: nil}
  # Longer than any amount or address a person types; the inputs stop there too.
  @form_limits %{
    "action" => 16,
    "amount" => 64,
    "for_other" => 16,
    "receiver" => 64,
    "acknowledged" => 16
  }
  @claims [
    {"claim_usdc", "Claim USDC"},
    {"claim_regent", "Claim REGENT"},
    {"claim_and_restake_regent", "Claim and restake"}
  ]
  @claim_steps Enum.map(@claims, &elem(&1, 0))

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> OnchainSteps.init()
     |> assign(
       active: nil,
       action: "stake",
       amount: "",
       form: @blank_form,
       wallet: nil,
       refusals: %{}
     )}
  end

  # A different wallet's figures are not this one's: what was typed for the
  # last one is cleared.
  @impl true
  def update(assigns, socket) do
    socket =
      if Map.has_key?(assigns, :wallet) and assigns.wallet != socket.assigns.wallet,
        do: assign(socket, amount: "", form: %{socket.assigns.form | acknowledged: nil}),
        else: socket

    {:ok,
     socket
     |> assign(
       Map.take(assigns, [
         :id,
         :staking,
         :status,
         :wallet,
         :linked,
         :notice,
         :reading,
         :shared_reading
       ])
     )
     |> sync()}
  end

  @impl true
  def handle_event("onchain_active_wallet", params, socket) do
    active = OnchainSteps.active_wallet(params)
    send(self(), {:stake_active_wallet, active})

    socket =
      if active == socket.assigns.active, do: socket, else: assign(socket, press_note: nil)

    {:noreply, socket |> assign(active: active) |> sync()}
  end

  def handle_event("select_staking_action", %{"mode" => mode}, socket)
      when mode in ["stake", "unstake"] do
    if mode == socket.assigns.action do
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> assign(action: mode, amount: "", form: %{socket.assigns.form | acknowledged: nil})
       |> sync()}
    end
  end

  def handle_event("fill_staking_amount", %{"portion" => portion}, socket)
      when portion in ["half", "max"] do
    case Staking.spendable(socket.assigns.staking, socket.assigns.action) do
      :unavailable ->
        {:noreply, socket}

      amount ->
        {:noreply,
         socket |> assign(amount: StakeLive.token_amount(portioned(amount, portion))) |> sync()}
    end
  end

  def handle_event("change", params, socket) do
    case EventInput.texts(params, @form_limits) do
      {:ok, %{"amount" => amount} = fields} ->
        {:noreply,
         socket
         |> assign(amount: amount, form: change_form(socket.assigns.form, fields, params))
         |> sync()}

      _unreadable ->
        {:noreply, assign(socket, press_note: EventInput.unreadable())}
    end
  end

  # A press made before the review caught up with the form: the form is taken
  # as the page's own, and the reply carries the review for it and the step the
  # pressed button now stands for.
  def handle_event("prepare_and_send", %{"form" => form, "step" => name}, socket)
      when is_binary(name) do
    case EventInput.texts(form, @form_limits) do
      {:ok, fields} -> prepare(socket |> apply_form(fields) |> sync(), name)
      :error -> {:reply, %{}, assign(socket, press_note: EventInput.unreadable())}
    end
  end

  def handle_event("step_sent", params, socket),
    do: {:noreply, OnchainSteps.sent(socket, params)}

  def handle_event("step_failed", %{"step" => name, "reason" => reason}, socket)
      when is_binary(name) and failure_reason(reason) do
    {:noreply, assign(socket, press_note: failure_note(reason, name, socket.assigns))}
  end

  def handle_event("check_again", %{"hash" => hash}, socket) when is_binary(hash),
    do: {:noreply, OnchainSteps.check_again(socket, hash)}

  # Anything else the page sent is not in a shape this panel takes.
  def handle_event(_event, _params, socket),
    do: {:noreply, assign(socket, press_note: EventInput.unreadable())}

  # A step that landed moved this wallet's figures and the contract's, so the
  # page reads both again, and the steps follow what the new reading says. A
  # step Base turned down keeps the reason the reading gave when it answered.
  @impl true
  def handle_async({:onchain_step, hash}, result, socket) do
    socket = OnchainSteps.checked(socket, hash, result)

    case entry(socket, hash) do
      %{outcome: :confirmed} ->
        SnapshotCache.refresh_soon()
        send(self(), :stake_step_landed)
        {:noreply, socket}

      %{outcome: :reverted} = entry ->
        refusal = contract_limit(entry, socket.assigns.staking)
        {:noreply, update(socket, :refusals, &Map.put(&1, hash, refusal))}

      _entry ->
        {:noreply, socket}
    end
  end

  defp prepare(%{assigns: %{review: nil}} = socket, _name), do: {:reply, %{}, socket}

  defp prepare(%{assigns: %{review: review}} = socket, name) do
    send = if name in @claim_steps, do: name, else: next_step(socket.assigns)
    {:reply, %{review: review, send: send}, socket}
  end

  # The review follows the signer and the form. With no eligible signer there is
  # no review, and every press says why nothing was sent.
  defp sync(socket) do
    %{linked: linked, active: active, staking: staking} = socket.assigns
    signer = OnchainSteps.signer(linked, active)

    review =
      if signer,
        do:
          Review.new(
            socket.assigns.id,
            signer,
            ChainClient.base(),
            Steps.steps(signer, staking, staking_form(socket.assigns)),
            inputs(socket.assigns)
          )

    OnchainSteps.put_review(socket, review)
  end

  defp staking_form(assigns),
    do: Map.merge(assigns.form, %{action: assigns.action, amount: assigns.amount})

  # The form as the page shows it, field for field: the warning box is only
  # there once a receiving address is.
  defp inputs(assigns) do
    %{
      "action" => assigns.action,
      "amount" => assigns.amount,
      "for_other" => to_string(assigns.form.for_other),
      "receiver" => assigns.form.receiver
    }
    |> Map.merge(
      if receiver(assigns.form),
        do: %{"acknowledged" => to_string(Steps.acknowledged?(assigns.form))},
        else: %{}
    )
  end

  # Ticking the warning acknowledges exactly the address shown; any change to
  # the address or to the choice to stake for someone else takes it back.
  defp change_form(form, fields, params) do
    receiver = Map.get(fields, "receiver", form.receiver)
    for_other = fields["for_other"] == "true"

    acknowledged =
      cond do
        params["_target"] == ["acknowledged"] -> acknowledge(fields["acknowledged"], receiver)
        receiver != form.receiver or for_other != form.for_other -> nil
        true -> form.acknowledged
      end

    %{for_other: for_other, receiver: receiver, acknowledged: acknowledged}
  end

  defp apply_form(socket, form) do
    current = socket.assigns.form
    receiver = text(form["receiver"])

    acknowledged =
      if form["acknowledged"] == "true" and receiver == current.receiver,
        do: current.acknowledged

    assign(socket,
      action:
        if(form["action"] in ~w(stake unstake), do: form["action"], else: socket.assigns.action),
      amount: text(form["amount"]),
      form: %{
        for_other: form["for_other"] == "true",
        receiver: receiver,
        acknowledged: acknowledged
      }
    )
  end

  defp text(value) when is_binary(value), do: value
  defp text(_value), do: ""

  defp acknowledge("true", receiver) do
    case Steps.other_address(receiver) do
      :error -> nil
      address -> address
    end
  end

  defp acknowledge(_unticked, _receiver), do: nil

  # The step the primary button sends: the approval while one is needed and none
  # from this wallet is still on its way to Base, then the action itself.
  defp next_step(%{review: nil, action: action}), do: action

  defp next_step(%{review: review, action: action, presses: presses}) do
    if Review.find(review, "approve") && not Presses.on_its_way?(presses, review, "approve"),
      do: "approve",
      else: action
  end

  defp approval_note(%{review: nil}), do: nil

  defp approval_note(%{review: review} = assigns) do
    cond do
      is_nil(Review.find(review, "approve")) ->
        nil

      next_step(assigns) == "approve" ->
        "Staking needs a one-time REGENT approval first. Approve it, then stake."

      true ->
        "Approval sent. You can stake now; if the approval has not landed yet, the stake will not go through."
    end
  end

  # What the primary button sends, read from the review itself, so a press sends
  # what the page shows.
  defp review_line(%{review: nil}), do: nil

  defp review_line(%{review: review} = assigns) do
    case {Review.find(review, assigns.action), next_step(assigns)} do
      {nil, _step} ->
        nil

      {_step, "approve"} ->
        "Approve REGENT lets the staking contract take any amount of your REGENT when you stake, so you only approve once. Stake REGENT sends it next."

      {_step, "stake"} ->
        stake_line(review)

      {_step, "unstake"} ->
        "You unstake #{amount(review)} REGENT. You get #{amount(review)} REGENT back in your wallet."
    end
  end

  defp stake_line(%{inputs: %{"for_other" => "true", "receiver" => receiver}} = review),
    do:
      "You pay #{amount(review)} REGENT. #{RegentFormat.short_address(String.trim(receiver))} gets the stake."

  defp stake_line(review),
    do: "You pay #{amount(review)} REGENT. You get #{amount(review)} REGENT staked."

  defp amount(%{inputs: %{"amount" => amount}}), do: String.trim(amount)

  defp entry(socket, hash), do: Enum.find(socket.assigns.presses.sent, &(&1.hash == hash))

  # A press with no step behind it says what on the form is missing; every other
  # reason has the shared words.
  defp failure_note("step_unknown", name, %{linked: linked, active: active} = assigns)
       when name in ~w(approve stake unstake) and is_list(linked) and is_binary(active) do
    (OnchainSteps.signer(linked, active) && missing(name, staking_form(assigns))) ||
      OnchainSteps.failure_note("step_unknown", linked, active, "Base")
  end

  defp failure_note(reason, _name, %{linked: linked, active: active}),
    do: OnchainSteps.failure_note(reason, linked, active, "Base")

  defp missing(name, form) do
    cond do
      match?({:error, _}, Staking.parse_amount(form.amount)) ->
        "Enter an amount in REGENT above zero. Nothing was sent."

      name != "unstake" and Steps.receiver(form) == {:error, :receiver_invalid} ->
        "Enter a valid receiving address. Nothing was sent."

      name != "unstake" and Steps.receiver(form) == {:error, :receiver_unacknowledged} ->
        "Tick the warning about the receiving address first. Nothing was sent."

      true ->
        nil
    end
  end

  # Each sent step as the page shows it, newest first. A stake Base turned down
  # says so when the reading at the time showed staking paused or full.
  defp shown(presses, refusals) do
    for entry <- Presses.shown(presses) do
      shown = OnchainSteps.describe(entry, "Base")

      %{
        hash: entry.hash,
        title: title(entry.name, entry.review),
        state: shown.state,
        words: step_words(shown.state, entry, refusals) || shown.words,
        href: "https://basescan.org/tx/#{entry.hash}"
      }
    end
  end

  defp step_words(:confirmed, entry, _refusals), do: confirmed(entry.name, entry.review)

  defp step_words(:reverted, entry, refusals),
    do: turned_down(refusals[entry.hash]) || reverted(entry.name)

  defp step_words(_state, _entry, _refusals), do: nil

  # Only a stake, or a claim that restakes, is refused while staking is paused
  # or would take the contract past what it can hold.
  defp contract_limit(%{name: "claim_and_restake_regent"}, %{} = staking),
    do: Staking.limit_refusal(staking, "claim_and_restake_regent", nil)

  defp contract_limit(%{name: "stake", review: %{} = review}, %{} = staking) do
    {:ok, raw} = Staking.parse_amount(amount(review))
    Staking.limit_refusal(staking, "stake", raw)
  end

  defp contract_limit(_entry, _staking), do: nil

  defp turned_down(:staking_paused),
    do: "Staking is paused on Base right now, so this did not go through and nothing moved."

  defp turned_down(:amount_above_capacity),
    do:
      "The staking contract cannot take that much more REGENT, so this did not go through and nothing moved."

  defp turned_down(_limit), do: nil

  defp title("approve", _review), do: "REGENT approval"

  defp title("stake", %{inputs: %{"for_other" => "true", "receiver" => receiver}} = review),
    do: "Stake #{amount(review)} REGENT for #{RegentFormat.short_address(String.trim(receiver))}"

  defp title("stake", %{} = review), do: "Stake #{amount(review)} REGENT"
  defp title("unstake", %{} = review), do: "Unstake #{amount(review)} REGENT"
  defp title("claim_usdc", _review), do: "USDC claim"
  defp title("claim_regent", _review), do: "REGENT claim"
  defp title("claim_and_restake_regent", _review), do: "Claim and restake"
  defp title(_name, _review), do: "Transaction"

  defp confirmed("approve", _review), do: "Approved. You can stake now."

  defp confirmed("stake", %{inputs: %{"for_other" => "true"}}),
    do: "Done. The receiving address owns this stake."

  defp confirmed("stake", _review), do: "Done. Your position is updating."
  defp confirmed("unstake", _review), do: "Done. The REGENT is back in your wallet."
  defp confirmed("claim_usdc", _review), do: "Done. Your USDC rewards were claimed."
  defp confirmed("claim_regent", _review), do: "Done. Your REGENT rewards were claimed."

  defp confirmed("claim_and_restake_regent", _review),
    do: "Done. Your REGENT rewards were added to your stake."

  defp reverted("approve"),
    do: "The approval did not go through and nothing moved. Press Approve REGENT again."

  defp reverted("stake"),
    do:
      "The stake did not go through and nothing moved. This usually means the approval had not landed yet, or the amount is more than the wallet holds. Check both, then press Stake REGENT again."

  defp reverted("unstake"),
    do:
      "The unstake did not go through and nothing moved. Check the amount is not more than you have staked, then try again."

  defp reverted("claim_usdc"),
    do: "The claim did not go through and nothing moved. There may be no USDC to claim yet."

  defp reverted("claim_regent"),
    do:
      "The claim did not go through and nothing moved. There may be no REGENT rewards to claim yet, or not enough in the reward pool."

  defp reverted("claim_and_restake_regent"),
    do:
      "The claim did not go through and nothing moved. There may be no REGENT rewards to restake yet, or staking may be paused."

  defp portioned(balance, "half"), do: div(balance, 2)
  defp portioned(balance, "max"), do: balance

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        signed_in: is_list(assigns.linked),
        wallet_ready: wallet_ready?(assigns.staking, assigns.wallet),
        preview: position_preview(assigns),
        claims: claims(Staking.available_claims(assigns.staking)),
        receiver: receiver(assigns.form),
        receiver_invalid: receiver_invalid?(assigns.form),
        spendable: Staking.spendable(assigns.staking, assigns.action),
        amount_notice: amount_notice(assigns),
        next_step: next_step(assigns),
        approval_note: approval_note(assigns),
        review_line: review_line(assigns),
        mismatch_note: OnchainSteps.mismatch_note(assigns.linked, assigns.active),
        sent: shown(assigns.presses, assigns.refusals)
      )

    ~H"""
    <section
      id={@id}
      phx-hook="OnchainSteps"
      class="stake-actions rg-panel rg-panel--surface rg-panel__body"
      aria-labelledby="staking-actions-heading"
      data-staking-mode={@action}
    >
      <div class="stake-section-heading">
        <div>
          <p class="stake-section-kicker">Your next move</p>
          <h2 id="staking-actions-heading">
            {if @wallet, do: "Manage your stake", else: "Stake in three steps"}
          </h2>
        </div>
        <span :if={@wallet} class="stake-signer" title={@wallet}>
          <span aria-hidden="true"></span>{RegentFormat.short_address(@wallet)}
        </span>
      </div>

      <div :if={!@wallet} class="stake-connect-flow">
        <ol>
          <li>
            <span>1</span><p><strong>Connect</strong> an Ethereum wallet.</p>
          </li>
          <li>
            <span>2</span><p><strong>Choose</strong> how much REGENT to stake.</p>
          </li>
          <li>
            <span>3</span><p><strong>Confirm</strong> each Base transaction in your wallet.</p>
          </li>
        </ol>
        <Regent.Primitives.button
          type="button"
          class="stake-primary"
          data-account-target={if @signed_in, do: "connect-wallet", else: "sign-in"}
        >
          Connect wallet
        </Regent.Primitives.button>
        <p class="stake-fine-print">
          Signing in connects your wallet. Nothing is sent until you confirm it in your wallet.
        </p>
      </div>

      <StakeLive.notice :if={@wallet && @notice} notice={@notice} />

      <Loading.panel
        :if={@wallet && !@wallet_ready}
        id={
          if @reading || @status == :loading,
            do: "staking-wallet-skeleton",
            else: "staking-wallet-unavailable"
        }
        label="Your wallet position"
        labels={["Available REGENT", "Currently staked", "Claimable USDC", "Claimable REGENT"]}
        loading={@reading || @status == :loading}
      />

      <div :if={@wallet_ready} id="staking-wallet-controls" class="stake-wallet-controls">
        <p :if={is_integer(@staking.wallet_block_number)} class="stake-wallet-block">
          Your position at Base block #{TokenDisplay.count(@staking.wallet_block_number)}.
        </p>
        <p :if={@staking.wallet_block_number == :unavailable} class="stake-wallet-block">
          Your position could not be read just now. Everything else here is current, and every
          action below still goes to your wallet.
        </p>
        <dl
          id="staking-wallet-summary"
          class="stake-wallet-summary"
          phx-hook="MotionCount"
          data-variant={AshPlatformWeb.Motion.standard("count")}
        >
          <.metric label="Available REGENT" amount={@staking.wallet_token_balance} unit="REGENT" />
          <.metric label="Currently staked" amount={@staking.wallet_stake_balance} unit="REGENT" />
          <.metric label="Claimable USDC" amount={@staking.wallet_claimable_usdc} unit="USDC" />
          <.metric
            label="Claimable REGENT"
            amount={@staking.wallet_claimable_regent}
            unit="REGENT"
          />
        </dl>

        <div
          id="staking-modes"
          class="stake-modes"
          phx-hook="MotionTabs"
          data-active={@action}
          data-variant={AshPlatformWeb.Motion.standard("tabs")}
        >
          <div class="stake-mode" role="tablist" aria-label="Stake or unstake">
            <Regent.Primitives.button
              :for={mode <- modes()}
              variant="secondary"
              type="button"
              phx-click={
                if @action == mode,
                  do:
                    JS.transition("is-mode-hinted",
                      to: "#staking-amount-form .stake-submit",
                      time: 650,
                      blocking: false
                    ),
                  else: "select_staking_action"
              }
              phx-target={@myself}
              phx-value-mode={mode}
              role="tab"
              id={"staking-tab-#{mode}"}
              data-tab={mode}
              aria-selected={to_string(@action == mode)}
              aria-controls="staking-tabpanel"
            >{mode_label(mode)}</Regent.Primitives.button>
            <span
              class="stake-mode__ink"
              data-ink
              aria-hidden="true"
              phx-mounted={JS.ignore_attributes(["style"])}
            ></span>
          </div>

          <div id="staking-tabpanel" role="tabpanel" aria-labelledby={"staking-tab-#{@action}"}>
            <form id="staking-amount-form" phx-change="change" phx-target={@myself}>
              <input type="hidden" name="action" value={@action} data-onchain-input="action" />
              <Regent.Primitives.field id="staking-amount" label="Amount">
                <div class="stake-amount">
                  <input
                    id="staking-amount"
                    name="amount"
                    value={@amount}
                    maxlength="64"
                    inputmode="decimal"
                    autocomplete="off"
                    placeholder="0.0"
                    phx-debounce="200"
                    data-onchain-input="amount"
                    aria-describedby="staking-available staking-amount-feedback"
                  />
                  <span>REGENT</span>
                </div>
              </Regent.Primitives.field>
              <div class="stake-amount-tools">
                <div class="stake-amount-action">
                  <Regent.Primitives.button
                    id="staking-primary"
                    class={"stake-primary stake-submit" <> armed_class(@amount)}
                    type="button"
                    data-onchain-step={@signed_in && @next_step}
                    data-account-target={!@signed_in && "sign-in"}
                    phx-mounted={JS.ignore_attributes(["data-awaiting-wallet"])}
                  ><.press_label label={primary_label(@next_step, @action)} /></Regent.Primitives.button>
                  <p id="staking-available">
                    Available
                    <TokenDisplay.amount amount={spendable_figure(@spendable)} unit="REGENT" />
                  </p>
                </div>
                <div class="stake-amount-shortcuts">
                  <Regent.Primitives.button
                    variant="secondary"
                    type="button"
                    phx-click="fill_staking_amount"
                    phx-target={@myself}
                    phx-value-portion="half"
                    disabled={not fillable?(@spendable, "half")}
                  >50%</Regent.Primitives.button>
                  <Regent.Primitives.button
                    variant="secondary"
                    type="button"
                    phx-click="fill_staking_amount"
                    phx-target={@myself}
                    phx-value-portion="max"
                    disabled={not fillable?(@spendable, "max")}
                  >Max</Regent.Primitives.button>
                </div>
              </div>
              <%!-- Always on the page, so the fields after it keep their focus while it fills. --%>
              <p
                id="staking-review"
                class="stake-review"
                aria-live="polite"
                hidden={!(@signed_in && @review_line)}
              >
                {@signed_in && @review_line}
              </p>
              <.mismatch :if={@signed_in} note={@mismatch_note} />
              <p
                id="staking-amount-feedback"
                class="stake-amount-notice"
                role="status"
                data-visible={to_string(not is_nil(@amount_notice))}
              >
                {@amount_notice}
              </p>

              <div id="staking-recipient-controls" class="stake-recipient" hidden={@action != "stake"}>
                <label class="stake-check" for="staking-for-other">
                  <input
                    id="staking-for-other"
                    name="for_other"
                    type="checkbox"
                    value="true"
                    checked={@form.for_other}
                    data-onchain-input="for_other"
                    aria-controls="staking-recipient-fields"
                    aria-expanded={to_string(@form.for_other)}
                  />
                  <span>Stake for a different address</span>
                </label>
                <div id="staking-recipient-fields" hidden={!@form.for_other}>
                  <Regent.Primitives.field id="staking-recipient" label="Receiving Ethereum address">
                    <input
                      id="staking-recipient"
                      name="receiver"
                      type="text"
                      maxlength="64"
                      value={@form.receiver}
                      autocomplete="off"
                      spellcheck="false"
                      autocapitalize="none"
                      placeholder="0x…"
                      phx-debounce="200"
                      data-onchain-input="receiver"
                      aria-describedby="staking-recipient-error"
                      aria-invalid={to_string(@receiver_invalid)}
                    />
                  </Regent.Primitives.field>
                  <p id="staking-recipient-error" role="status" hidden={!@receiver_invalid}>
                    Enter a valid Ethereum wallet address. ENS names, the zero address and the staking contract are not accepted.
                  </p>
                  <label
                    :if={@receiver}
                    id="staking-recipient-warning"
                    class="stake-check"
                    for="staking-recipient-acknowledged"
                  >
                    <input
                      id="staking-recipient-acknowledged"
                      name="acknowledged"
                      type="checkbox"
                      value="true"
                      checked={Steps.acknowledged?(@form)}
                      data-onchain-input="acknowledged"
                    />
                    <span id="staking-recipient-warning-text">
                      Warning: the wallet {@receiver} will accrue the USDC revenue and REGENT rewards, and only that wallet may withdraw the tokens.
                    </span>
                  </label>
                </div>
              </div>

              <dl :if={@preview} class="stake-preview" aria-label="Estimated position after action">
                <div>
                  <dt>Position after</dt><dd>
                    <TokenDisplay.amount amount={@preview.position} unit="REGENT" />
                  </dd>
                </div>
                <div>
                  <dt>USDC Revenue Share</dt><dd>{@preview.revenue_share}</dd>
                </div>
              </dl>

              <p :if={@signed_in && @approval_note} class="stake-approval-note">
                {@approval_note}
              </p>
            </form>
          </div>
        </div>

        <.activity sent={@sent} press={@press_note} myself={@myself} />

        <section class="stake-rewards" aria-labelledby="staking-rewards-heading">
          <div>
            <p class="stake-section-kicker">Available rewards</p>
            <h3 id="staking-rewards-heading">Claim or compound</h3>
          </div>
          <div class="stake-button-row">
            <Regent.Primitives.button
              :for={claim <- @claims}
              id={"staking-#{claim.action}"}
              type="button"
              class={if claim.claimable, do: "stake-claim-ready"}
              data-claim={claim.action}
              data-onchain-step={@signed_in && claim.action}
              data-account-target={!@signed_in && "sign-in"}
              phx-mounted={JS.ignore_attributes(["data-awaiting-wallet"])}
            ><.press_label label={claim.label} /><span class="visually-hidden">{claim_state(
              claim.claimable
            )}</span></Regent.Primitives.button>
          </div>
          <.mismatch :if={@signed_in} note={@mismatch_note} />
        </section>

        <div class="stake-footer">
          <Regent.Primitives.button
            variant="secondary"
            type="button"
            phx-click="refresh_data"
            disabled={@reading || @shared_reading}
          >
            {if @reading || @shared_reading, do: "Updating…", else: "Refresh Data"}
          </Regent.Primitives.button>
        </div>
      </div>
    </section>
    """
  end

  attr :label, :string, required: true
  attr :amount, :any, default: nil
  attr :unit, :string, required: true

  defp metric(assigns) do
    ~H"""
    <div class="stake-metric">
      <dt>{@label}</dt><dd><TokenDisplay.amount amount={@amount} unit={@unit} /></dd>
    </div>
    """
  end

  attr :label, :string, required: true

  # The words swap for "Confirm in wallet" while the wallet has this button's
  # press. The button itself keeps taking presses.
  defp press_label(assigns) do
    ~H"""
    <span data-press-label>{@label}</span><span data-wallet-wait>Confirm in wallet</span>
    """
  end

  attr :note, :string, default: nil

  # Only the wallet the wallet app has open can act, and only when it is one of
  # the account's own. When it is not, both are named so the person can switch.
  defp mismatch(assigns) do
    ~H"""
    <p :if={@note} class="shell-sending-wallet" role="note">{@note}</p>
    """
  end

  attr :sent, :list, required: true
  attr :press, :string, default: nil
  attr :myself, :any, required: true

  # What happened to each press, newest first, read on Base by the server.
  defp activity(assigns) do
    ~H"""
    <section id="staking-activity" class="stake-activity" aria-label="Your transactions">
      <p :if={@press} id="staking-press-notice" class="stake-notice" role="alert">{@press}</p>
      <ol :if={@sent != []} class="stake-sent" aria-live="polite">
        <li :for={entry <- @sent} id={"staking-sent-#{entry.hash}"} data-outcome={entry.state}>
          <strong>{entry.title}</strong>
          <span>{entry.words}</span>
          <a href={entry.href} target="_blank" rel="noopener noreferrer">
            View on BaseScan <span aria-hidden="true">↗</span>
          </a>
          <Regent.Primitives.button
            :if={entry.state == :stalled}
            variant="secondary"
            type="button"
            phx-click="check_again"
            phx-target={@myself}
            phx-value-hash={entry.hash}
          >Check again</Regent.Primitives.button>
        </li>
      </ol>
    </section>
    """
  end

  defp amount_notice(%{staking: nil}), do: nil

  defp amount_notice(%{staking: staking, action: action, amount: amount}) do
    case amount |> String.trim() |> Staking.parse_amount() do
      {:ok, requested} -> staking |> Staking.limit_refusal(action, requested) |> limit_copy()
      {:error, _} -> blank_or_invalid(amount)
    end
  end

  defp blank_or_invalid(amount),
    do: if(String.trim(amount) == "", do: nil, else: "Enter an amount in REGENT above zero.")

  defp limit_copy(nil), do: nil

  # Nothing here refuses the amount: the figure it would be checked against is
  # missing, and the wallet still decides.
  defp limit_copy(:chain_unavailable),
    do: "Your position is unavailable right now, so this amount is not checked against it."

  defp limit_copy(:staking_paused), do: "Staking is paused on Base right now."
  defp limit_copy(:amount_above_balance), do: "That is more REGENT than this wallet holds."

  defp limit_copy(:amount_above_capacity),
    do: "That is more REGENT than the staking contract can still take."

  defp limit_copy(:amount_above_stake), do: "That is more REGENT than this wallet has staked."

  defp position_preview(%{staking: nil}), do: nil

  defp position_preview(%{staking: staking, action: action, amount: amount}) do
    with {:ok, requested} <- Staking.parse_amount(amount),
         {:ok, current_position} <- atomic(staking.wallet_stake_balance_raw) do
      position =
        if action == "stake",
          do: current_position + requested,
          else: max(current_position - requested, 0)

      %{
        position: StakeLive.token_amount(position),
        revenue_share: revenue_share(position, staking.regent_total_supply_raw)
      }
    else
      _ -> nil
    end
  end

  # Revenue is accounted against the whole supply, so a staker's share of it is
  # their position over the total supply. Four decimals are always shown, the
  # fifth dropped rather than rounded up, as every other share on this page is.
  defp revenue_share(position, total_supply_raw) do
    case atomic(total_supply_raw) do
      {:ok, total_supply} when total_supply > 0 ->
        position
        |> Decimal.new()
        |> Decimal.mult(100)
        |> Decimal.div(Decimal.new(total_supply))
        |> Decimal.round(4, :down)
        |> Decimal.to_string(:normal)
        |> Kernel.<>("%")

      _unavailable ->
        "0.0000%"
    end
  end

  defp atomic(value) when is_binary(value) do
    case Integer.parse(value) do
      {amount, ""} -> {:ok, amount}
      _ -> :error
    end
  end

  defp atomic(_), do: :error

  # Every claim control is offered. The last reading from Base decides which of
  # them is lit, so a reward that is actually waiting stands out before the
  # contract answers for itself.
  defp claims(available) do
    for {action, label} <- @claims do
      %{action: action, label: label, claimable: is_nil(Map.get(available, action))}
    end
  end

  # The glow is a colour, so the same news is carried in the control's name for
  # anyone who does not see it.
  defp claim_state(true), do: "(available)"
  defp claim_state(false), do: "(nothing to claim)"

  # What the amount controls may fill in, or nothing at all when the figure they
  # would count from could not be read. Filling a box is not a wallet request,
  # so these two are the only controls on this page a reading ever quiets.
  defp spendable_figure(:unavailable), do: :unavailable
  defp spendable_figure(spendable), do: StakeLive.token_amount(spendable)

  # An entered amount lights the action the way a pointer resting on it would.
  # It is appearance only; the press reaches the wallet either way.
  defp armed_class(amount) do
    case Staking.parse_amount(amount) do
      {:ok, _requested} -> " is-armed"
      _invalid -> ""
    end
  end

  defp fillable?(:unavailable, _portion), do: false
  defp fillable?(spendable, "half"), do: div(spendable, 2) > 0
  defp fillable?(spendable, "max"), do: spendable > 0

  defp wallet_ready?(staking, wallet) when is_map(staking) and is_binary(wallet),
    do: Map.get(staking, :wallet_address) == wallet

  defp wallet_ready?(_, _), do: false

  # The address the warning names: one a stake may go to, typed in while staking
  # for someone else.
  defp receiver(%{for_other: true, receiver: input}) do
    case Steps.other_address(input) do
      :error -> nil
      address -> address
    end
  end

  defp receiver(_form), do: nil

  defp receiver_invalid?(%{for_other: true, receiver: input}),
    do: String.trim(input) != "" and Steps.other_address(input) == :error

  defp receiver_invalid?(_form), do: false

  defp primary_label("approve", _action), do: "Approve REGENT"
  defp primary_label(_step, action), do: "#{mode_label(action)} REGENT"

  defp modes, do: ~w(stake unstake)

  defp mode_label("stake"), do: "Stake"
  defp mode_label("unstake"), do: "Unstake"
end
