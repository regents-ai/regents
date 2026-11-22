defmodule RegentsWeb.Keyfleet.WalletPanel do
  @moduledoc """
  One group of Keyfleet's wallet buttons: the form they read, the line naming
  what a press sends, the buttons, and every step sent from them with how it
  landed. The ash-template repository's `skills/onchain-buttons` has the
  rules; `RegentsWeb.Keyfleet.OnchainSteps` holds the parts every group shares.
  In the page, Keyfleet's own hook `KeyfleetOnchainSteps`
  (`assets/js/keyfleet/hooks/onchain_steps.ts`) sends its steps through the
  site's one wallet connection.

  The steps are built on the server by `Regents.Keyfleet.WalletSteps` for the one
  wallet that may send them: Privy's active wallet, when the signed-in account
  links it. The page receives them before anyone presses. With another wallet
  active, or none, the figures are built for the account's own wallet without
  its network fee, which no press pays, and a press sends nothing and names
  the wallet to open; another wallet active is named in a note too. Those
  figures never bring steps to the page, even when that wallet opens before
  they land: they show without steps, and a press has its steps built. Signed
  out, nothing is built; the Key on sale, the daily split's preview, presence
  and the launch still show their figures, read from the chain the same way,
  and all but Buy without their buttons.

  Nothing here disables, hides or holds back a button while anything is
  pending: every press reaches the wallet, and the contract decides. The one
  exception is a step the chain's own state, read at the latest block, makes
  certain to fail (`blocked/2`): `step_button/1` keeps it in view, disabled,
  with a few words saying why, and for a signed-in person the steps are built
  again every few seconds while any is blocked, so it comes back when that
  state changes. A press that asks for its steps and finds it so is answered
  with those same words. A visitor's Buy follows the sale as a purchase does,
  every few minutes.

  The browser's own agent presses with its values over the form's, and its
  steps are built from those for that press alone and judged the same way,
  so what the person typed, and the steps and figures shown, stay as they
  are. What its press tells the panel is marked as the agent's, and every
  answer, a refusal, a wallet that sends nothing or a step sent, reaches the
  agent alone: the note below the person's buttons and their form stay as
  they are.

  The page renders it with `live_component`, giving:

    * `id`, `flow` (a `Regents.Keyfleet.WalletSteps` flow), `fleet` (its `fleet_id`
      and `chain_id`), `actor` (the signed-in person, or nil), `lease`
      (the page's `session_lease`, which each of the panel's events and
      results checks first, taking the account as it reads now:
      `RegentsWeb.Live.Session.check_component_lease/2`) and `client_tag`
      (the page's: the panel's first figures read once it is mounted, each
      one a changed form or a change of open wallet starts, each one the panel
      starts again by itself, after figures it could not read, while a
      button is held back and Buy's every few minutes, the one Buy REGENT's
      press starts as it clears its amount, and each press's, spends one of
      its address's `keyfleet_wallet_reads`, and past them the panel shows
      it could not read its figures, as when the chain does not answer, and
      tries again, counted; a rebuild the page itself causes and the account
      changing are not counted. No press is held back for them:
      past them a signed-in press is answered with the steps the panel holds
      when they were built for exactly what it asks for, the wallet, whether
      that wallet sends, the fields of the form the steps read, the proposal,
      Key and advance, and otherwise with steps built then, and a signed-out
      one reads nothing and keeps the figures shown);
    * `inputs`, each field the steps read with its first value; `proposal`,
      `token_id` or `advance_id` when the flow acts on one; `refresh`, anything whose
      change means the steps are built again; `names_sender`, false where
      the page leaves out the line naming the wallet a press is sent from;
      `tool`, the browser tool in Keyfleet's
      `priv/keyfleet/tool_manifest.json` that presses these buttons for a
      browser's own agent, if any, which the page names on the panel's root
      (the page's tool itself comes with its own slice); and `class`;
    * the slots `heading`, `fields`, `notes`, `buttons` and `details` (the
      last under what was sent), each given the panel's state (`inputs`,
      `built`, `review`, `presses`, `signer`, `signed_out`) to read.

  Buttons name their step with `data-onchain-step` and sit outside the form;
  fields that feed the steps carry `data-onchain-input` with the name they
  are built from, and a text field is `box/1` long: a value longer as typed
  than the site takes from it is refused, and said, before anything is built
  (`RegentsWeb.Keyfleet.BoxLimit`); the steps' own rules may refuse more once they
  have trimmed it. Signed out, a button also carries
  `data-account-target="sign-in"`, so its press opens sign-in instead.

  When a step sent from it goes through, the chain is read again
  (`RegentsWeb.Keyfleet.OnchainSteps.checked/3`) and the page that renders it receives
  `{:onchain_landed, fleet_id}`.
  """
  use RegentsWeb, :live_component

  alias RegentChain.{Presses, Review}
  alias Regents.Account.Actors.Human
  alias Regents.Keyfleet.Proposals
  alias Regents.Keyfleet.WalletSteps
  alias Regents.Keyfleet.WalletSteps.VoteSteps
  alias Regents.Limits
  alias RegentsWeb.Keyfleet.BoxLimit
  alias RegentsWeb.Keyfleet.OnchainSteps
  alias RegentsWeb.Keyfleet.WalletWords
  alias RegentsWeb.Live.Session

  # A purchase is good for ten minutes from the block it was built at, so
  # the steps are built again well before that.
  @rebuild_buy_ms 300_000
  # How soon a group whose figures couldn't be read tries again.
  @reread_ms 10_000
  # How soon a group with a button the chain's state holds back reads it again.
  @blocked_ms 15_000
  # How long a press waits on its own steps before it is answered without them.
  @press_build_ms 8_000
  # The groups whose figures a visitor sees.
  @shown_to_visitors [:buy, :run_split, :present, :launch_upkeep]
  # The groups a visitor sees without their buttons: Buy stays, and a press
  # asks for sign-in.
  @read_only_for_visitors [:run_split, :present, :launch_upkeep]
  # A group whose figures couldn't be read.
  @unread %{review: nil, figures: %{}, problem: :unread}

  @doc "Whether the steps built for the group name `step`."
  def has_step?(%{built: %{review: %{} = review}}, step), do: Review.find(review, step) != nil
  def has_step?(_panel, _step), do: false

  @doc "The figures the group's steps were built from, or an empty map before."
  def figures(%{built: %{figures: figures}}), do: figures
  def figures(_panel), do: %{}

  @doc """
  Why the chain's own state makes `step` certain to fail now, or nil: a
  fleet whose Keys are all sold holds Buy back. A step that waits on an
  approval is pressable as soon as the approval is sent from this group,
  before it lands: a pending transaction is never a reason.
  """
  def blocked(%{built: %{problem: :sold_out}}, "buy"), do: :sold_out

  def blocked(panel, step) do
    reason = panel |> figures() |> Map.get(:blocked, %{}) |> Map.get(step)

    if reason in [:approve_first, :approve_usdc_first] and sent?(panel, "approve"),
      do: nil,
      else: reason
  end

  attr :panel, :map, required: true, doc: "the panel's state, as its slots are given it"
  attr :step, :string, required: true
  attr :id, :string, required: true
  attr :variant, :string, default: "primary"

  attr :done, :boolean,
    default: false,
    doc: "marks a step that has landed, as Approve once it has"

  slot :inner_block, required: true

  @doc """
  One wallet button: it names its step, and when the chain's own state makes
  that step certain to fail it stays in view, disabled, with why beside it.
  Signed out, its press opens sign-in.
  """
  def step_button(assigns) do
    assigns = assign(assigns, reason: blocked(assigns.panel, assigns.step))

    ~H"""
    <span class="wallet-panel-step">
      <Regent.Primitives.button
        id={@id}
        variant={@variant}
        data-onchain-step={@step}
        data-account-target={@panel.signed_out && "sign-in"}
        data-done={@done}
        disabled={@reason != nil}
        aria-describedby={@reason && "#{@id}-why"}
      >
        <span data-press-label>{render_slot(@inner_block)}</span>
      </Regent.Primitives.button>
      <span :if={@reason} id={"#{@id}-why"} class="wallet-panel-why">
        {WalletWords.blocked(@reason)}
      </span>
    </span>
    """
  end

  @doc "Whether `step` has been sent and has not been turned down."
  def sent?(%{presses: presses}, step),
    do: Enum.any?(presses.sent, &(&1.name == step and &1.outcome in [:pending, :confirmed]))

  @doc """
  Whether an approval sent from this group has landed and the figures read
  since hold no step back for want of one: Approve is then shown done.
  """
  def approved?(%{presses: presses} = panel) do
    landed? = Enum.any?(presses.sent, &(&1.name == "approve" and &1.outcome == :confirmed))
    held = panel |> figures() |> Map.get(:blocked, %{}) |> Map.values()

    landed? and not Enum.any?(held, &(&1 in [:approve_first, :approve_usdc_first]))
  end

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> Session.check_component_lease(&take_account/2)
     |> OnchainSteps.init()
     |> assign(
       active: nil,
       signer: nil,
       built: nil,
       mismatch: nil,
       inputs: %{},
       proposal: nil,
       token_id: nil,
       advance_id: nil,
       refresh: nil,
       tool: nil,
       names_sender: true,
       class: nil,
       heading: [],
       fields: [],
       notes: [],
       details: [],
       rebuild: nil,
       shown: nil
     )}
  end

  @impl true
  # The group's own timer: only the latest one builds the steps again, and
  # its read is counted, whatever it follows.
  def update(%{rebuild: timer}, socket) do
    {:ok, if(timer == socket.assigns.rebuild, do: sync(socket, :counted), else: socket)}
  end

  def update(assigns, socket) do
    changed? = &(Map.get(assigns, &1) != Map.get(socket.assigns, &1))
    moved? = Enum.any?([:actor, :fleet, :proposal, :token_id, :advance_id], changed?)
    rebuild? = moved? or changed?.(:refresh)
    # The page gives `fleet` on every render, so a group without one has just
    # mounted. Once the page is connected, when a read can start, that first
    # read is counted, since one page mounts many groups.
    spend =
      if connected?(socket) and not Map.has_key?(socket.assigns, :fleet),
        do: :counted,
        else: :uncounted

    # What was typed stays; a field the page gives later starts from the
    # value it gives.
    inputs = assigns |> Map.get(:inputs, %{}) |> Map.merge(socket.assigns.inputs) |> kept()
    socket = socket |> assign(Map.delete(assigns, :inputs)) |> assign(inputs: inputs)
    socket = if moved?, do: drop_built(socket), else: socket

    {:ok, if(rebuild?, do: sync(socket, spend), else: socket)}
  end

  @impl true
  # The page reports the open wallet whenever Privy's state moves. The wallet
  # the group already holds, none included, starts no read and spends
  # nothing; another one is taken and its figures read, counted.
  def handle_event("onchain_active_wallet", params, %{assigns: %{active: held}} = socket) do
    case OnchainSteps.active_wallet(params) do
      ^held -> {:noreply, socket}
      _other -> {:noreply, socket |> take_active(params) |> sync(:counted)}
    end
  end

  def handle_event("change", params, socket) when is_map(params),
    do: {:noreply, socket |> take_inputs(params) |> sync(:counted)}

  # A press made before its step reached the page, before the steps caught up
  # with the form, or of a button the chain's state holds back: the form and
  # the open wallet are taken as the page's own, and the reply carries the
  # steps built from them, read now even where the chain is read, so the press
  # never waits on steps still being read elsewhere; past the address's
  # wallet-read allowance, the steps held when they were built for exactly
  # this press (`press_built/2`). A page that has just joined again can ask
  # before it reports the wallet.
  def handle_event("prepare_and_send", %{"form" => form, "step" => step} = params, socket)
      when is_map(form) and is_binary(step) do
    socket = socket |> take_inputs(form) |> take_active(params) |> sync_now()

    case refusal(socket, socket.assigns, step) do
      nil -> {:reply, %{review: socket.assigns.review, send: step}, socket}
      refused -> {:reply, counted(socket, refused), assign(socket, press_note: refused.note)}
    end
  end

  # The browser's own agent's press, with its values over the form's: the
  # steps are built from those, now, for this press alone, and judged as the
  # page judges its own, while the form and the steps the page shows stay as
  # they are. What is sent from them is followed as any other press, and a
  # proposal's words are saved as its steps are handed over. A refusal is
  # counted and goes only in the reply: the note below the buttons speaks for
  # the person's own presses. Past the address's wallet-read allowance, the
  # steps held answer it when they were built for exactly what it asks for
  # (`press_built/2`); no press is refused for it.
  def handle_event("prepare_for_agent", %{"form" => form, "step" => step} = params, socket)
      when is_map(form) and is_binary(step) do
    {socket, wallet} = socket |> take_active(params) |> follow_signer()
    inputs = over(socket.assigns.inputs, form)
    built = if wallet, do: press_built(socket, request(socket, wallet, inputs))
    pressed = %{socket.assigns | inputs: inputs, built: built, review: sendable(built, socket)}

    case refusal(socket, pressed, step) do
      nil ->
        save_words(pressed, step, inputs)

        {:reply, %{review: pressed.review, send: step},
         OnchainSteps.remember(socket, pressed.review)}

      refused ->
        {:reply, counted(socket, refused), socket}
    end
  end

  # The press is heard just before the wallet is asked to send it, with the
  # form it was built from. The browser agent's press, sent from steps the
  # page already holds, is heard marked as the agent's (`"agent" => true`):
  # its proposal's words are saved, and the person's form stays as it is.
  def handle_event("step_pressed", %{"step" => "propose", "form" => form}, socket) do
    save_words(socket.assigns, "propose", form)
    {:noreply, socket}
  end

  def handle_event("step_pressed", %{"agent" => true}, socket), do: {:noreply, socket}

  # The person's Buy REGENT clears its amount once the wallet has the press,
  # so the form starts over for the next one, and its figures are read again,
  # counted.
  def handle_event(
        "step_pressed",
        %{"step" => "convert"},
        %{assigns: %{flow: :convert}} = socket
      ),
      do:
        {:noreply,
         socket |> assign(inputs: %{socket.assigns.inputs | "amount" => ""}) |> sync(:counted)}

  def handle_event("step_sent", params, socket), do: {:noreply, OnchainSteps.sent(socket, params)}

  # The wallet sent nothing, or may have: counted, and for the person's own
  # press the note below the buttons says why. The agent hears it in its
  # own answer.
  def handle_event("step_failed", params, socket) do
    case Presses.failed(params) do
      {:ok, _step, reason} ->
        RegentsWeb.Keyfleet.Telemetry.wallet_failed(socket.assigns.flow, reason)
        {:noreply, noted(socket, params, reason)}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("check_again", %{"hash" => hash}, socket) when is_binary(hash),
    do: {:noreply, OnchainSteps.check_again(socket, hash)}

  # Any other event, and any of these sent without the values it takes,
  # changes nothing and has no reply.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  # A step that has landed changes what the next one needs (an approval, a
  # vote, what is waiting), so the steps are built again. One that went
  # through may have moved the fleet's money: `OnchainSteps.checked/3` has
  # asked for the chain to be read again, and the page is told
  # (`{:onchain_landed, fleet_id}`), so its other figures are read again too.
  def handle_async({:onchain_step, hash}, result, socket) do
    socket = OnchainSteps.checked(socket, hash, result)

    case Enum.find(socket.assigns.presses.sent, &(&1.hash == hash)) do
      %{outcome: :confirmed} ->
        send(self(), {:onchain_landed, socket.assigns.fleet.fleet_id})
        {:noreply, sync(socket)}

      %{outcome: :reverted} ->
        {:noreply, sync(socket)}

      _still_reading ->
        {:noreply, socket}
    end
  end

  # Figures land only while the wallet they were read for is still the one
  # shown; a build for another is dropped, and the one for the shown wallet
  # follows.
  def handle_async(:build, {:ok, {wallet, built}}, %{assigns: %{shown: wallet}} = socket),
    do: {:noreply, show(socket, built)}

  def handle_async(:build, {:ok, _other_wallet}, socket), do: {:noreply, socket}

  def handle_async(:build, {:exit, _reason}, socket), do: {:noreply, show(socket, @unread)}

  # The signed-in person as the sign-in reads now. A wallet unlinked since
  # leaves the panel at once: its steps go and the figures follow the wallets
  # the account still links.
  defp take_account(socket, account) do
    actor = Human.for_account(account)

    if actor == socket.assigns.actor,
      do: socket,
      else: socket |> assign(actor: actor) |> drop_built() |> sync()
  end

  # Privy's active wallet as the page reported it. Another wallet clears the
  # note about the one open before. It says only which wallet is open: steps
  # are built for it only when the account links it (`OnchainSteps.signer/2`).
  defp take_active(socket, params) do
    active = OnchainSteps.active_wallet(params)
    socket = if active == socket.assigns.active, do: socket, else: assign(socket, press_note: nil)
    assign(socket, active: active)
  end

  defp take_inputs(socket, params),
    do: assign(socket, inputs: over(socket.assigns.inputs, params))

  # `params` over `inputs`: each field the form has that `params` names, as
  # its box keeps it.
  defp over(inputs, params) do
    typed =
      for {name, _first} <- inputs, is_binary(params[name]), into: %{}, do: {name, params[name]}

    inputs |> Map.merge(typed) |> kept()
  end

  @doc """
  The `maxlength` of the box for the form field `name`: two more than the
  longest value the site takes from it (`RegentsWeb.Keyfleet.BoxLimit`).
  """
  def box(name), do: BoxLimit.maxlength(Map.fetch!(boxes(), name))

  # The longest value the site takes from each box a group's form may have,
  # in UTF-16 units as typed, by its field's name: a proposal's text fields
  # as many units as the bytes `Regents.Keyfleet.WalletSteps.VoteSteps` keeps of them
  # once trimmed (a letter is never fewer bytes than units, so the longest it
  # keeps fits, and it refuses more itself); an amount, a wallet, days and a
  # Keys list as the signed API takes them; and room for any Key's number and
  # any share, rate or address written out. Each field the steps are built
  # from is held to it before they are built (`read/2`).
  defp longest do
    [key: 20, target: 20] ++
      VoteSteps.field_bytes() ++
      [share: 100, recipient: 100, rate: 100, amount: 100, wallet: 100, days: 10, keys: 1_000]
  end

  defp boxes, do: Map.new(longest(), fn {name, units} -> {"#{name}", units} end)

  # Each value as its box keeps it, so none is drawn back longer than its
  # box: one the page gave first, and one an agent or any other sender put
  # in the form, as a browser keeps a paste.
  defp kept(inputs) do
    boxes = boxes()

    Map.new(inputs, fn {name, value} ->
      case boxes do
        %{^name => units} -> {name, BoxLimit.kept(value, units)}
        _no_box -> {name, value}
      end
    end)
  end

  # The first field, in the order above, holding more than the site takes.
  defp too_long(inputs) do
    Enum.find_value(longest(), fn {name, units} ->
      if inputs |> Map.get("#{name}", "") |> BoxLimit.too_long?(units),
        do: {:too_long, name, units}
    end)
  end

  # The fields the steps are built from: a proposal's own kind's
  # (`VoteSteps.fields/1`), so a field of a kind not chosen, which stays in the
  # form unseen, never holds a press back; and the whole form of any other
  # group, whose every field is read.
  defp read(:propose, inputs), do: Map.take(inputs, VoteSteps.fields(inputs["kind"]))
  defp read(_flow, inputs), do: inputs

  # The steps follow the wallet that may send them and the form. The figures
  # are built for that wallet, or for the account's own while another is
  # active; the page is given steps only for the wallet that may send them.
  # A group's first read, one the page's changed form or open wallet starts,
  # and one its own timer starts, is `:counted`.
  defp sync(socket, spend \\ :uncounted) do
    {socket, figures_wallet} = follow_signer(socket)
    build(socket, figures_wallet, spend)
  end

  # As `sync/1`, but built before it returns. A build still being read lands
  # later with the same steps, and the page keeps every review a press was
  # sent from. A press's read is counted, and no press is held back for it:
  # signed in, as `press_built/2` says; signed out, past the allowance, the
  # figures shown stay.
  defp sync_now(socket) do
    case follow_signer(socket) do
      {socket, nil} ->
        build(socket, nil, :pressed)

      {socket, wallet} ->
        socket
        |> assign(shown: wallet)
        |> show(press_built(socket, request(socket, wallet, socket.assigns.inputs)))
    end
  end

  # The steps for a signed-in press, built now from what it asks for. Its
  # read spends one of the page's address's `keyfleet_wallet_reads`; past
  # them, the steps the panel holds answer it when they were built for exactly
  # what it asks for (`built_for/1`), and otherwise they are built now all the
  # same.
  defp press_built(socket, request) do
    wanted = built_for(request)

    case {Limits.spend(:keyfleet_wallet_reads, socket.assigns.client_tag), socket.assigns} do
      {:limited, %{built: %{review: %{}, built_for: ^wanted} = built}} -> built
      _read_now -> bounded_build(request, wanted)
    end
  end

  # A press's steps are built under `Regents.Keyfleet.PressBuilds` while the
  # page waits up to `@press_build_ms`. A build that raises, or is not done by
  # then, answers the press as one the chain could not be read for, built for
  # what it asks for.
  defp bounded_build(request, wanted) do
    task =
      Task.Supervisor.async_nolink(Regents.Keyfleet.PressBuilds, fn -> build_steps!(request) end)

    case Task.yield(task, @press_build_ms) || Task.shutdown(task) do
      {:ok, built} -> built
      _unanswered -> Map.put(@unread, :built_for, wanted)
    end
  end

  # What a build's steps were read for besides the chain: the wallet, whether
  # that wallet sends them (only then is its network fee judged), the fields
  # of the form the steps read (`read/2`), and the proposal, Key and advance.
  defp built_for(%{flow: flow, signer: signer, params: params}),
    do: Map.put(%{params | inputs: read(flow, params.inputs)}, :signer, signer)

  defp follow_signer(socket) do
    linked = linked(socket)
    signer = OnchainSteps.signer(linked, socket.assigns.active)

    socket =
      socket
      |> assign(
        signer: signer,
        mismatch: OnchainSteps.mismatch_note(linked, socket.assigns.active)
      )
      |> drop_other_signer(signer)

    {socket, signer || List.first(linked || [])}
  end

  # Steps and figures built for another person, fleet, proposal, Key or advance
  # leave at once, before new ones are read: nothing here speaks for what the
  # panel showed before, and a press finds no step and asks for the ones built
  # from what it shows now.
  defp drop_built(socket), do: socket |> assign(built: nil) |> OnchainSteps.put_review(nil)

  # Steps built for a wallet that may no longer send leave the page at once,
  # before new ones are read.
  defp drop_other_signer(%{assigns: %{review: %{signer: shown}}} = socket, signer)
       when shown != signer,
       do: OnchainSteps.put_review(socket, nil)

  defp drop_other_signer(socket, _signer), do: socket

  defp build(%{assigns: %{actor: nil, flow: flow}} = socket, nil, spend)
       when flow in @shown_to_visitors do
    %{fleet: %{fleet_id: fleet_id}, token_id: token_id} = socket.assigns

    socket
    |> OnchainSteps.put_review(nil)
    |> assign(shown: nil)
    |> read_figures(spend, fn ->
      built =
        fleet_id
        |> WalletSteps.read_figures!(flow, %{token_id: token_id})
        |> Map.put(:review, nil)

      {nil, built}
    end)
  end

  defp build(socket, nil, _spend),
    do: socket |> assign(built: nil, shown: nil) |> OnchainSteps.put_review(nil)

  # Every group reads the chain, so its steps are built away from the page's
  # own process.
  defp build(socket, wallet, spend) do
    request = request(socket, wallet, socket.assigns.inputs)

    socket
    |> assign(shown: wallet)
    |> read_figures(spend, fn -> {wallet, build_steps!(request)} end)
  end

  # A counted read, and a signed-out press's, spends one of the page's
  # address's `keyfleet_wallet_reads` (`Regents.Limits`); past them nothing is
  # read: the group shows its figures could not be read, trying again as it
  # does then, and for a signed-out press keeps the figures it shows.
  defp read_figures(socket, :uncounted, read), do: start_async(socket, :build, read)

  defp read_figures(socket, spend, read) do
    case {Limits.spend(:keyfleet_wallet_reads, socket.assigns.client_tag), spend} do
      {:ok, _spend} -> start_async(socket, :build, read)
      {:limited, :counted} -> show(socket, @unread)
      {:limited, :pressed} -> socket
    end
  end

  defp request(socket, wallet, inputs) do
    %{assigns: assigns} = socket

    %{
      fleet_id: assigns.fleet.fleet_id,
      flow: assigns.flow,
      signer: wallet,
      component_id: assigns.id,
      params: %{
        sending: wallet == assigns.signer,
        inputs: inputs,
        proposal: assigns.proposal,
        token_id: assigns.token_id,
        advance_id: assigns.advance_id
      },
      actor: assigns.actor
    }
  end

  # A box the steps are built from holding more than the site takes from it
  # is refused, and said, before any step is built from the form. Each build
  # carries what it was built for (`built_for/1`), so it lands and leaves with
  # it.
  defp build_steps!(request) do
    built =
      case too_long(read(request.flow, request.params.inputs)) do
        nil ->
          WalletSteps.build_steps!(
            request.fleet_id,
            request.flow,
            request.signer,
            request.component_id,
            request.params,
            actor: request.actor
          )

        problem ->
          %{review: nil, figures: %{}, problem: problem}
      end

    Map.put(built, :built_for, built_for(request))
  end

  defp show(socket, built) do
    socket
    |> assign(built: built)
    |> OnchainSteps.put_review(sendable(built, socket))
    |> rebuild_later(built)
  end

  # The review of `built` when it was built to be sent by the wallet that may
  # send it now (`built_for/1`), or nil. Steps read for a wallet's figures
  # while it was not the one sending, with no network fee judged, show their
  # figures and no steps; a press then builds its own.
  defp sendable(
         %{review: %{} = review, built_for: %{signer: signer, sending: true}},
         %{assigns: %{signer: signer}}
       ),
       do: review

  defp sendable(_built, _socket), do: nil

  defp rebuild_later(socket, %{problem: :unread}), do: rebuild_in(socket, @reread_ms)

  # A visitor's press sends none of these steps, so a held-back button is no
  # reason to read the chain again; Buy's figures follow the sale as they do
  # for anyone.
  defp rebuild_later(%{assigns: %{actor: nil, flow: :buy}} = socket, _built),
    do: rebuild_in(socket, @rebuild_buy_ms)

  defp rebuild_later(%{assigns: %{actor: nil}} = socket, _built), do: socket

  defp rebuild_later(socket, %{figures: %{blocked: blocked}}) when blocked != %{},
    do: rebuild_in(socket, @blocked_ms)

  defp rebuild_later(%{assigns: %{flow: :buy}} = socket, _built),
    do: rebuild_in(socket, @rebuild_buy_ms)

  defp rebuild_later(socket, _built), do: socket

  defp rebuild_in(socket, ms) do
    timer = make_ref()
    send_update_after(socket.assigns.myself, %{rebuild: timer}, ms)
    assign(socket, rebuild: timer)
  end

  defp linked(%{assigns: %{actor: %{wallet_addresses: wallets}}}), do: wallets
  defp linked(_socket), do: nil

  defp failure_note(socket, reason),
    do:
      OnchainSteps.failure_note(reason, linked(socket), socket.assigns.active, chain_name(socket))

  # Why `step` is not handed over from `pressed`, the panel as the press was
  # built, as the reply to the press, or nil when it is: its `reason`, its
  # `note` in the person's words, and its `cause`, "values" when a value the
  # press sent is why, a field the steps were built from or the choice
  # pressed, so the press with another one may go through, or "state" when
  # the chain's or the page's own state alone is, so the same press goes
  # through once that changes. No wallet here may send it: what is wrong with
  # the form, or else the note for the wallet the press named. The chain's
  # state makes it certain to fail: the words beside its button. The steps
  # have none of that name, as when the form can't be built from: what is
  # wrong with the form, that the network can't be reached when the chain
  # could not be read for them, or else that it can't be sent as it stands.
  defp refusal(socket, pressed, step) do
    reason = blocked(pressed, step)

    cond do
      pressed.review == nil ->
        unknown(socket, pressed)

      reason ->
        %{
          reason: "blocked",
          cause: held_cause(pressed, reason),
          note: WalletWords.blocked(reason)
        }

      Review.find(pressed.review, step) == nil ->
        unknown(socket, pressed)

      true ->
        nil
    end
  end

  # Steps the chain could not be read for, for a wallet that may send them:
  # the network can't be reached, and the same press may go through later.
  defp unknown(%{assigns: %{signer: signer}}, %{built: %{problem: :unread}})
       when is_binary(signer),
       do: %{
         reason: "step_unknown",
         cause: "state",
         note: "Can’t reach the network right now. Nothing was sent. Press again."
       }

  defp unknown(socket, pressed) do
    case form_problem(pressed) do
      nil -> %{reason: "step_unknown", cause: "state", note: failure_note(socket, "step_unknown")}
      note -> %{reason: "step_unknown", cause: problem_cause(pressed.built.problem), note: note}
    end
  end

  # Refused, and nothing reaches the wallet: counted under its reason. The
  # page reports nothing more for this press.
  defp counted(socket, %{reason: reason} = refused) do
    RegentsWeb.Keyfleet.Telemetry.wallet_failed(socket.assigns.flow, reason)
    refused
  end

  # A step the chain's state holds back for a value typed is held back for
  # that value: the Key or Keys named, the wallet or the amount, when the
  # steps were built from that field. A Yes or Abstain while the proposal
  # takes only No is held back for the choice pressed, since No is taken.
  # Any other reason is the chain's state alone, such as a sale not open yet,
  # a Key too new to propose with, or a Buy REGENT that no amount from 1 USDC
  # up gets through.
  defp held_cause(_pressed, :only_no), do: "values"

  defp held_cause(pressed, reason) do
    read = read(pressed.flow, pressed.inputs)
    if Enum.any?(typed_for(reason), &Map.has_key?(read, &1)), do: "values", else: "state"
  end

  # What is wrong with the form is a value typed, except where the page's
  # state alone is why: a proposal, launch or advance not there, a token that
  # hasn't said its decimals, a Key that is given, never sold or claimed so.
  defp problem_cause(problem)
       when problem in [
              :not_recorded,
              :no_launch,
              :advance_unknown,
              :decimals_unknown,
              :not_for_sale,
              :not_club
            ],
       do: "state"

  defp problem_cause(_problem), do: "values"

  defp typed_for(:not_your_key), do: ["key", "keys"]
  defp typed_for(:own_wallet), do: ["wallet"]
  defp typed_for(reason) when reason in [:above_outstanding, :not_enough], do: ["amount"]
  defp typed_for({:too_big, nil}), do: []
  defp typed_for({:too_big, _largest}), do: ["amount"]
  defp typed_for(_reason), do: []

  # The note for the person's own press, written below the buttons; the
  # agent hears what the wallet answered its press in its own answer.
  defp noted(socket, %{"agent" => true}, _reason), do: socket

  defp noted(socket, _params, reason),
    do: assign(socket, press_note: failure_note(socket, reason))

  # What is wrong with the form, in the words of the line above the buttons,
  # which names the field and what it takes; nil when the line says nothing
  # is (a sold-out fleet says so beside its Buy button instead).
  defp form_problem(%{built: %{problem: problem}} = assigns) when problem not in [nil, :unread],
    do: line(assigns)

  defp form_problem(_assigns), do: nil

  # A proposal's words are saved as soon as its press is heard, before the
  # wallet sends it, from the form its steps are built from, so the chain
  # reader finds them when it lands. They are saved only when those steps
  # found the wallet may vote the Key the form names: one that may not can't
  # make the proposal. A person's press never waits on this; an agent's words
  # are saved once its steps are built, as they are handed over. A save that
  # fails leaves the proposal without its words on the page.
  defp save_words(
         %{flow: :propose, built: %{figures: %{governs?: true}}} = panel,
         "propose",
         %{"text" => text}
       )
       when is_binary(text),
       do: Proposals.save_words(panel.fleet.fleet_id, text, panel.actor)

  defp save_words(_panel, _step, _form), do: :ok

  defp chain_name(%{assigns: %{fleet: %{chain_id: chain_id}}}) do
    case WalletSteps.chain(chain_id) do
      %{name: name} -> name
      nil -> "the fleet’s network"
    end
  end

  # A purchase's figures are on its buttons, so its line says only why its
  # steps couldn't be built.
  defp line(%{flow: :buy, built: %{problem: nil}}), do: nil
  defp line(assigns), do: WalletWords.line(assigns.flow, assigns.built, assigns.inputs)

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        panel:
          assigns
          |> Map.take([:inputs, :built, :review, :presses, :signer])
          |> Map.put(:signed_out, assigns.actor == nil),
        line: line(assigns),
        chain: chain_name(%{assigns: assigns}),
        read_only: assigns.actor == nil and assigns.flow in @read_only_for_visitors
      )

    ~H"""
    <section
      id={@id}
      class={["wallet-panel", @class]}
      phx-hook="KeyfleetOnchainSteps"
      data-webmcp-tool={@tool}
      data-webmcp-fleet={@tool && @fleet.fleet_id}
    >
      {render_slot(@heading, @panel)}

      <form
        :if={@fields != []}
        id={"#{@id}-form"}
        class="wallet-panel-form"
        phx-change="change"
        phx-submit="change"
        phx-target={@myself}
      >
        {render_slot(@fields, @panel)}
      </form>

      {render_slot(@notes, @panel)}

      <%!-- Lines above the buttons stay in the page and are only hidden, so
           one appearing never moves the button a person is about to press. --%>
      <p id={"#{@id}-line"} class="wallet-panel-line" aria-live="polite" hidden={!@line}>
        {@line}
      </p>
      <p :if={@names_sender} id={"#{@id}-from"} class="wallet-panel-note" hidden={!@signer}>
        <%= if @signer do %>
          Sending from <Regent.Primitives.address id={"#{@id}-signer"} address={@signer} />
          on {@chain}.
        <% end %>
      </p>
      <p id={"#{@id}-mismatch"} class="wallet-panel-note" hidden={!@mismatch}>
        {@mismatch}
      </p>

      <div :if={!@read_only} class="wallet-panel-buttons">
        {render_slot(@buttons, @panel)}
      </div>

      <p :if={@press_note} id={"#{@id}-press-note"} class="wallet-panel-note" role="status">
        {@press_note}
      </p>
      <p class="wallet-panel-note" role="status" data-onchain-lost hidden>
        This page lost its connection, so nothing was sent. Press again once it's back.
      </p>

      <ol
        :if={@presses.sent != []}
        id={"#{@id}-sent"}
        class="wallet-panel-sent"
        aria-live="polite"
      >
        <li
          :for={
            {entry, shown} <-
              Enum.map(
                Presses.shown(@presses),
                &{&1, WalletWords.outcome(&1, OnchainSteps.describe(&1, @chain))}
              )
          }
          data-state={shown.state}
        >
          <strong>{WalletWords.title(entry)}</strong>
          <span>{shown.words}</span>
          <Regent.Primitives.address id={"#{@id}-sent-#{entry.hash}"} address={entry.hash} kind="tx" />
          <Regent.Primitives.button
            :if={shown.state == :stalled}
            variant="quiet"
            phx-click="check_again"
            phx-value-hash={entry.hash}
            phx-target={@myself}
          >
            Check again
          </Regent.Primitives.button>
        </li>
      </ol>

      {render_slot(@details, @panel)}
    </section>
    """
  end
end
