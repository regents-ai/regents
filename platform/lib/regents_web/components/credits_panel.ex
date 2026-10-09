defmodule RegentsWeb.CreditsPanel do
  @moduledoc """
  The Buy Credits panel: the balance, the amount, the wallet presses and what
  each press did, all in one place. Credits are bought with USDC on Base. Built like Stake and Redeem on
  `RegentsWeb.OnchainSteps`: the server builds the steps
  (`RegentCredits.Chains.steps/3`), every press goes straight to the wallet, and
  each sent Buy is reported as a purchase once the chain holds it, then checked
  every two seconds until it counts. The site's Oban keeps checking once a minute after the page stops.

  Each press asks the wallet onto Base before it sends. The USDC the paying
  wallet holds on Base is shown.

  Buy is disabled only when it is certain to fail, from the chain at the latest
  block: the Base approval does not cover the amount yet, or the wallet holds
  too little USDC. Explanations wait in tips; the panel shows figures, choices,
  presses and outcomes.

  The wallet figures are read when the paying wallet changes, when the panel
  opens or comes back into view, after each press and once a step lands; never
  on an amount edit. Each read draws on the visitor's `RegentsWeb.ChainReadBudget`;
  past it, the figures already shown stay.

  The parent passes `account` (the signed-in account), its `balance`
  (`RegentCredits.balance/1`, kept current by the parent), the visitor's
  `client_tag` and `id`.
  """
  use RegentsWeb, :live_component

  alias Regent.Primitives, as: P
  alias RegentChain.{Call, Presses, Review}
  alias RegentCredits.{Amount, Chains}
  alias RegentCredits.Errors.Refused
  alias Regents.{ChainClient, Credits, RateLimiter}
  alias RegentsWeb.{ChainReadBudget, OnchainSteps}

  @recheck_ms 2_000
  @block_ms 2_000
  @purchase_reads 150
  @report_tries 150

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> RegentsWeb.Live.Session.check_component_events(&take_account/2)
     |> OnchainSteps.init()
     |> assign(
       active: nil,
       signer: nil,
       amount: "5",
       number: Ecto.UUID.generate(),
       numbers: %{},
       usdc: nil,
       allowance: nil,
       purchases: %{}
     )}
  end

  @impl true
  def update(%{account: account} = assigns, socket) do
    {:ok,
     socket
     |> assign(
       id: assigns.id,
       lease: assigns.lease,
       balance: assigns.balance,
       client_tag: assigns.client_tag
     )
     |> take_account(account)}
  end

  @impl true
  def handle_event("onchain_active_wallet", params, socket) do
    active = OnchainSteps.active_wallet(params)
    socket = if active == socket.assigns.active, do: socket, else: assign(socket, press_note: nil)
    {:noreply, socket |> assign(active: active) |> sync()}
  end

  def handle_event("change", %{"amount" => amount}, socket),
    do: {:noreply, socket |> assign(amount: amount) |> sync()}

  # The page asks when the panel opens, when it comes back into view and after
  # each press, so the funds behind a disabled Buy are read again then.
  def handle_event("refresh_funds", _params, socket), do: {:noreply, read_funds(socket)}

  # A press made before the review caught up with the form: the form is taken
  # as the page's own, and the reply carries the review for it.
  def handle_event(
        "prepare_and_send",
        %{"form" => %{"amount" => amount}, "step" => name},
        socket
      )
      when is_binary(amount) do
    socket = socket |> assign(amount: amount) |> sync()

    case socket.assigns.review do
      %{} = review when is_binary(name) -> {:reply, %{review: review, send: name}, socket}
      _none -> {:reply, %{}, socket}
    end
  end

  def handle_event("step_sent", %{"transaction_hash" => hash} = params, socket)
      when is_binary(hash) do
    socket = OnchainSteps.sent(socket, params)

    case Enum.find(socket.assigns.presses.sent, &(&1.hash == String.downcase(hash))) do
      %{name: "buy", review: %{} = review} = entry ->
        {:noreply,
         socket
         |> put_purchase(entry.hash, %{purchase: :reporting, reads: 0})
         |> report(entry.hash, review, 0)}

      _other ->
        {:noreply, socket}
    end
  end

  def handle_event("step_failed", %{"reason" => reason}, socket) when is_binary(reason) do
    %{linked: linked, active: active, amount: amount} = socket.assigns
    note = amount_problem(amount) || OnchainSteps.failure_note(reason, linked, active, "Base")

    {:noreply, assign(socket, press_note: note)}
  end

  def handle_event("check_again", %{"hash" => hash}, socket),
    do: {:noreply, OnchainSteps.check_again(socket, hash)}

  def handle_event("check_purchase_again", %{"hash" => hash}, socket) do
    case socket.assigns.purchases do
      %{^hash => %{purchase: %{id: _id}} = shown} ->
        {:noreply, check_purchase(socket, hash, %{shown | reads: 0})}

      _unknown ->
        {:noreply, socket}
    end
  end

  # Once a step lands or reverts, the wallet's funds are read again a Base block
  # later: a read sent straight away can reach a node still a block behind and
  # answer with the figures from before the step.
  @impl true
  def handle_async({:onchain_step, hash}, result, socket) do
    socket = OnchainSteps.checked(socket, hash, result)

    case Enum.find(socket.assigns.presses.sent, &(&1.hash == hash)) do
      %{outcome: :pending} -> {:noreply, socket}
      entry -> {:noreply, socket |> approved(entry) |> read_funds(@block_ms)}
    end
  end

  def handle_async({:report, hash}, {:ok, {_review, _tries, {:ok, purchase}}}, socket),
    do: {:noreply, check_purchase(socket, hash, %{purchase: purchase, reads: 0})}

  def handle_async({:report, hash}, {:ok, {review, tries, answer}}, socket) do
    if again?(answer) and tries + 1 < @report_tries,
      do: {:noreply, report(socket, hash, review, tries + 1, @recheck_ms)},
      else: {:noreply, put_purchase(socket, hash, %{purchase: nil, reads: 0})}
  end

  def handle_async({:report, hash}, _unanswered, socket),
    do: {:noreply, put_purchase(socket, hash, %{purchase: nil, reads: 0})}

  def handle_async({:purchase, hash}, {:ok, {:ok, purchase}}, socket) do
    shown = %{purchase: purchase, reads: socket.assigns.purchases[hash].reads + 1}

    cond do
      purchase.status == :credited ->
        {:noreply, put_purchase(socket, hash, shown)}

      purchase.status == :checking and shown.reads < @purchase_reads ->
        {:noreply, check_purchase(socket, hash, shown)}

      true ->
        {:noreply, put_purchase(socket, hash, shown)}
    end
  end

  # An unanswered read counts like any other; the next one tries again.
  def handle_async({:purchase, hash}, _unanswered, socket) do
    %{purchase: purchase, reads: reads} = socket.assigns.purchases[hash]
    shown = %{purchase: purchase, reads: reads + 1}

    if shown.reads < @purchase_reads,
      do: {:noreply, check_purchase(socket, hash, shown)},
      else: {:noreply, put_purchase(socket, hash, shown)}
  end

  def handle_async(:usdc, {:ok, {:ok, micro}}, socket),
    do: {:noreply, assign(socket, usdc: micro)}

  def handle_async(:usdc, _unread, socket), do: {:noreply, assign(socket, usdc: :unread)}

  def handle_async(:allowance, {:ok, {:ok, micro}}, socket),
    do: {:noreply, assign(socket, allowance: micro)}

  def handle_async(:allowance, _unread, socket),
    do: {:noreply, assign(socket, allowance: :unread)}

  # A confirmed approval sets what staking may take to exactly its amount, so
  # the panel knows it from the receipt it just read, before the next read.
  defp approved(socket, %{
         name: "approve",
         outcome: :confirmed,
         review: %{inputs: %{"amount" => amount}}
       }),
       do: assign(socket, allowance: Chains.micro(dollars(amount)))

  defp approved(socket, _entry), do: socket

  # The review follows the signer and the amount. A new amount is a new
  # purchase number; a repeat press of the same review buys again under the
  # same number, which is a second purchase.
  defp sync(socket) do
    %{linked: linked, active: active, amount: amount} = socket.assigns
    signer = OnchainSteps.signer(linked, active)
    dollars = dollars(amount)
    inputs = %{"amount" => amount}

    socket =
      if {inputs, signer} == {socket.assigns[:inputs], socket.assigns.signer},
        do: socket,
        else: assign(socket, inputs: inputs, number: Ecto.UUID.generate())

    review =
      if signer do
        steps = if dollars, do: Chains.steps(:base, dollars, socket.assigns.number), else: []
        Review.new(socket.assigns.id, signer, Chains.chain(:base), steps, inputs)
      end

    # A new amount changes no balance, so only a new signer reads them.
    socket =
      if signer == socket.assigns.signer,
        do: socket,
        else: socket |> assign(signer: signer, usdc: nil, allowance: nil) |> read_funds()

    socket
    |> assign(mismatch: OnchainSteps.mismatch_note(linked, active))
    |> remember_number(review)
    |> OnchainSteps.put_review(review)
  end

  defp remember_number(socket, nil), do: socket

  defp remember_number(socket, review),
    do: assign(socket, numbers: Map.put(socket.assigns.numbers, review.id, socket.assigns.number))

  # A sent Buy is reported once the chain holds it: until then the report is
  # refused as not seen yet, and the page reports again every two seconds, for
  # up to five minutes. Each report counts against the person's report
  # allowance; past it, the page waits its turn the same way.
  defp report(socket, hash, review, tries, wait_ms \\ 0) do
    account = socket.assigns.account
    number = Map.fetch!(socket.assigns.numbers, review.id)

    start_async(socket, {:report, hash}, fn ->
      Process.sleep(wait_ms)
      {review, tries, send_report(account, review, number, hash)}
    end)
  end

  defp send_report(account, review, number, hash) do
    with :ok <- admit_report(account.privy_user_id) do
      RegentCredits.report_purchase(
        account.privy_user_id,
        review.signer,
        :base,
        dollars(review.inputs["amount"]),
        number,
        hash,
        actor: Credits.person(account)
      )
    end
  end

  defp admit_report(privy_user_id) do
    budget = Application.fetch_env!(:regents, :credits_report_rate_limit)

    case RateLimiter.admit(
           {:credits_report, privy_user_id},
           Keyword.fetch!(budget, :limit),
           Keyword.fetch!(budget, :window_seconds)
         ) do
      {:ok, _budget} -> :ok
      {:error, :rate_limited, _budget} -> :limited
    end
  end

  # Reported again: past the allowance, before the chain holds the Buy, or when
  # the chain could not be read. Any other refusal is final.
  defp again?(:limited), do: true

  defp again?({:error, %Ash.Error.Invalid{errors: errors}}),
    do: Enum.any?(errors, &match?(%Refused{reason: :not_seen_yet}, &1))

  defp again?({:error, %Ash.Error.Unknown{}}), do: true
  defp again?(_refused), do: false

  defp check_purchase(socket, hash, shown) do
    actor = Credits.person(socket.assigns.account)
    id = shown.purchase.id

    socket
    |> put_purchase(hash, shown)
    |> start_async({:purchase, hash}, fn ->
      Process.sleep(@recheck_ms)
      RegentCredits.check_purchase(id, actor: actor)
    end)
  end

  defp put_purchase(socket, hash, shown),
    do: assign(socket, purchases: Map.put(socket.assigns.purchases, hash, shown))

  # The paying wallet's USDC on Base, and what REGENT staking may take of it,
  # both at the latest block, `wait_ms` from now. A new read
  # replaces any still on its way, whose answer is then dropped.
  defp read_funds(socket, wait_ms \\ 0)

  defp read_funds(%{assigns: %{signer: nil}} = socket, _wait_ms), do: socket

  defp read_funds(socket, wait_ms) do
    case ChainReadBudget.admit(socket.assigns.client_tag) do
      :ok -> start_reads(socket, wait_ms)
      {:limited, _seconds} -> socket
    end
  end

  defp start_reads(socket, wait_ms) do
    signer = socket.assigns.signer

    socket
    |> start_async(:usdc, fn ->
      Process.sleep(wait_ms)
      usdc_call("balanceOf(address)", [signer])
    end)
    |> start_async(:allowance, fn ->
      Process.sleep(wait_ms)
      usdc_call("allowance(address,address)", [signer, Chains.staking()])
    end)
  end

  defp usdc_call(signature, args) do
    call = %{to: Chains.usdc(:base), data: Call.encode(signature, args)}

    with {:ok, "0x" <> hex} <-
           ChainClient.request(Chains.chain(:base), "eth_call", [call, "latest"]) do
      {:ok, String.to_integer(hex, 16)}
    end
  end

  # The account as the page gave it, or as it reads now before each event
  # (`RegentsWeb.Live.Session.check_component_events/2`): the wallets that may
  # act and the review follow it.
  defp take_account(socket, account),
    do: socket |> assign(account: account, linked: wallets(account)) |> sync()

  defp wallets(account), do: Enum.map(account.wallet_addresses, &String.downcase/1)

  defp dollars(amount) do
    case Integer.parse(String.trim(amount)) do
      {n, ""} when n in 5..500 -> n
      _not_whole_dollars -> nil
    end
  end

  # Why an amount can't be bought, in words for the person; nil when it can.
  defp amount_problem(amount) do
    case Integer.parse(String.trim(amount)) do
      {n, ""} when n in 5..500 -> nil
      {n, ""} when n < 5 -> "The minimum is 5 USDC."
      {n, ""} when n > 500 -> "The maximum is 500 USDC per purchase."
      _not_whole -> "Enter a whole number from 5 to 500."
    end
  end

  @impl true
  def render(assigns) do
    dollars = dollars(assigns.amount)

    assigns =
      assign(assigns,
        dollars: dollars,
        problem: amount_problem(assigns.amount),
        approve: approve_step(assigns, dollars),
        buy: step(assigns, "buy"),
        blocked: blocked(assigns, dollars)
      )

    ~H"""
    <section id={@id} class="credits-panel" phx-hook="OnchainSteps" data-refresh-funds>
      <header class="credits-panel__head">
        <dl
          id={"#{@id}-figures"}
          class="credits-panel__figures"
          phx-hook="MotionCount"
          data-variant="flash"
        >
          <div class="credits-panel__figure">
            <dt>Regents Credits</dt>
            <dd data-count>{figure(@balance.available)}</dd>
          </div>
          <div class="credits-panel__figure credits-panel__figure--small">
            <dt>In Bids</dt>
            <dd data-count>{figure(@balance.held)}</dd>
          </div>
        </dl>
        <.link class="credits-panel__history" navigate="/account/credits">
          Purchase History
        </.link>
      </header>

      <form
        id={"#{@id}-form"}
        class="credits-panel__form"
        phx-change="change"
        phx-submit="change"
        phx-target={@myself}
      >
        <label class="credits-panel__label" for={"#{@id}-amount"}>USDC Amount</label>
        <div class="credits-panel__amount" data-invalid={@problem && "true"}>
          <input
            id={"#{@id}-amount"}
            name="amount"
            value={@amount}
            inputmode="numeric"
            autocomplete="off"
            aria-describedby={"#{@id}-rate #{@id}-problem"}
            aria-invalid={@problem && "true"}
            data-onchain-input="amount"
          />
          <span aria-hidden="true">USDC</span>
        </div>
        <p id={"#{@id}-rate"} class="credits-panel__rate">1 USDC on Base buys 1 Regents Credit</p>
        <p
          id={"#{@id}-problem"}
          class="credits-panel__problem"
          role="alert"
          phx-hook="MotionRefusal"
          data-refused
          hidden={!@problem}
        >
          {@problem}
        </p>
      </form>

      <%!-- Lines above the buttons stay in the page and are only hidden, so one
           appearing never replaces the button a person has just pressed. --%>
      <div class="credits-panel__wallet" hidden={!@signer}>
        <span class="credits-panel__muted">Paying from</span>
        <code>{@signer && RegentFormat.short_address(@signer)}</code>
        <span class="credits-panel__usdc">{usdc(@usdc)}</span>
      </div>
      <p class="credits-panel__note" hidden={!@mismatch}>{@mismatch}</p>

      <ol class="credits-panel__steps">
        <li class="credits-panel__step" data-state={@approve.state}>
          <.check />
          <div class="credits-panel__step-words">
            <strong>
              Approve {@dollars && "#{@dollars} "}USDC
              <P.tip id={"#{@id}-approve-tip"} label="About approving">
                Lets REGENT staking take this USDC for your purchase. Each purchase needs its own approval.
              </P.tip>
            </strong>
            <span :if={@approve.words}>{@approve.words}</span>
          </div>
          <P.button variant="secondary" data-onchain-step="approve">Approve</P.button>
          <.check_again step={@approve} myself={@myself} />
        </li>
        <li class="credits-panel__step" data-state={@buy.state}>
          <.check />
          <div class="credits-panel__step-words">
            <strong>
              Buy {@dollars && "#{@dollars} "}Credits
              <P.tip id={"#{@id}-buy-tip"} label="About buying">
                Sends the USDC to REGENT staking. Your Credits arrive in about 2 seconds.
              </P.tip>
            </strong>
            <span :if={@buy.words}>{@buy.words}</span>
            <span :if={@buy.help?}>
              If USDC left your wallet, post the link in <a
                href="https://patchbay.help/credits-help"
                target="_blank"
                rel="noopener"
              >Credits help</a>.
            </span>
            <span :if={@blocked} id={"#{@id}-buy-why"}>{@blocked}</span>
          </div>
          <P.button
            data-onchain-step="buy"
            disabled={@blocked != nil}
            aria-describedby={@blocked && "#{@id}-buy-why"}
          >
            Buy
          </P.button>
          <.check_again step={@buy} myself={@myself} />
        </li>
      </ol>

      <p :if={@press_note} class="credits-panel__note" role="status">{@press_note}</p>
      <p class="credits-panel__note" role="status" data-onchain-lost hidden>
        Connection lost, so nothing was sent. Press again once it's back.
      </p>

      <footer class="credits-panel__legal">
        <a href="/terms">Terms of Service</a>
        <.link navigate="/credits/refunds">Refund Policy</.link>
      </footer>
    </section>
    """
  end

  defp check(assigns) do
    ~H"""
    <span class="credits-panel__check" aria-hidden="true">
      <svg viewBox="0 0 24 24"><path d="M5 12.5l4.5 4.5L19 7.5" /></svg>
    </span>
    """
  end

  attr :step, :map, required: true
  attr :myself, :any, required: true

  defp check_again(%{step: %{entry: entry, stalled?: true}} = assigns) do
    assigns = assign(assigns, event: check_event(entry), hash: entry.hash)

    ~H"""
    <P.button
      variant="quiet"
      class="credits-panel__again"
      phx-click={@event}
      phx-value-hash={@hash}
      phx-target={@myself}
    >
      Check again
    </P.button>
    """
  end

  defp check_again(assigns), do: ~H""

  defp check_event(%{name: "buy", review: %{}}), do: "check_purchase_again"
  defp check_event(_entry), do: "check_again"

  # The latest press of the named step for the form as it stands now: its state
  # (`:ready` before any), what it did in words, and whether it waits on a
  # Check again.
  defp step(assigns, name) do
    %{presses: %{sent: sent}, purchases: purchases, inputs: inputs} = assigns

    case Enum.find(sent, &(&1.name == name and match?(%{inputs: ^inputs}, &1.review))) do
      nil ->
        %{state: :ready, words: nil, help?: false, entry: nil, stalled?: false}

      entry ->
        shown = purchases[entry.hash]

        %{
          state: step_state(state(entry, shown)),
          words: words(entry, shown),
          help?: help?(shown),
          entry: entry,
          stalled?: stalled?(entry, shown)
        }
    end
  end

  # Approve shows what the chain says staking may take: done while that covers
  # the amount, whichever press made it so, and ready again once a Buy spends it.
  defp approve_step(assigns, dollars) do
    step = step(assigns, "approve")

    cond do
      step.state == :pending -> step
      covered?(assigns.allowance, dollars) -> %{step | state: :done, words: nil}
      step.state == :done -> %{step | state: :ready, words: nil}
      true -> step
    end
  end

  defp covered?(allowance, dollars) when is_integer(allowance) and is_integer(dollars),
    do: allowance >= Chains.micro(dollars)

  defp covered?(_allowance, _dollars), do: false

  # Why Buy is certain to fail right now, from the chain at the latest block; nil
  # when it may go through. An unread figure is never a reason.
  defp blocked(_assigns, nil), do: nil

  defp blocked(%{usdc: usdc, allowance: allowance}, dollars) do
    micro = Chains.micro(dollars)

    cond do
      is_integer(usdc) and usdc < micro -> "Not enough USDC on Base"
      is_integer(allowance) and allowance < micro -> "Approve first"
      true -> nil
    end
  end

  defp step_state(state) when state in [:confirmed, :credited], do: :done
  defp step_state(state) when state in [:pending, :checking, :stalled], do: :pending
  defp step_state(_failed), do: :failed

  defp stalled?(%{name: "buy"}, %{} = shown), do: purchase_stalled?(shown)
  defp stalled?(entry, nil), do: Presses.stalled?(entry)
  defp stalled?(_entry, _shown), do: false

  defp figure(amount),
    do: amount |> Amount.format() |> String.replace_suffix(" Credits", "")

  defp state(entry, nil), do: OnchainSteps.describe(entry, chain_name_of(entry)).state
  defp state(_entry, %{purchase: :reporting}), do: :checking
  defp state(_entry, %{purchase: nil}), do: :unrecorded
  defp state(_entry, %{purchase: purchase}), do: purchase.status

  # A step on its way or done shows as a mark; only trouble needs words.
  defp words(entry, nil) do
    case OnchainSteps.describe(entry, chain_name_of(entry)) do
      %{state: :pending} -> "Waiting for #{chain_name_of(entry)}"
      %{state: :confirmed} -> nil
      %{words: words} -> words
    end
  end

  defp words(entry, %{purchase: :reporting}), do: "Waiting for #{chain_name_of(entry)}"

  defp words(_entry, %{purchase: nil}),
    do: "Your wallet sent this, but this page couldn't record it."

  defp words(_entry, %{purchase: purchase} = shown) do
    case purchase do
      %{status: :credited, amount: amount} ->
        "#{Amount.format(amount)} added"

      %{status: :failed, reason: "reverted"} ->
        "Didn't go through. Nothing moved."

      %{status: :failed, reason: "already credited"} ->
        "Already counted."

      %{status: :failed, reason: "not found"} ->
        "Base never showed this payment. No Credits added."

      %{status: :failed} ->
        "Not the purchase this page prepared. No Credits added."

      %{status: :checking} ->
        checking_words(shown)
    end
  end

  # A sent payment the page couldn't match to a purchase points to Credits help.
  defp help?(%{purchase: nil}), do: true

  defp help?(%{purchase: %{status: :failed, reason: reason}}),
    do: reason not in ["reverted", "already credited", "not found"]

  defp help?(_shown), do: false

  defp checking_words(shown) do
    if purchase_stalled?(shown),
      do: "Still checking. It counts even if you close this page.",
      else: "Waiting for Base"
  end

  defp purchase_stalled?(%{purchase: %{status: :checking}, reads: reads}),
    do: reads >= @purchase_reads

  defp purchase_stalled?(_shown), do: false

  defp chain_name_of(%{review: %{chain: %{name: name}}}), do: name
  defp chain_name_of(_unknown), do: "the network"

  defp usdc(nil), do: "…"
  defp usdc(:unread), do: "unavailable"

  defp usdc(micro) do
    dollars = micro |> Decimal.new() |> Decimal.div(1_000_000) |> Decimal.round(2, :down)
    "#{Decimal.to_string(dollars, :normal)} USDC"
  end
end
