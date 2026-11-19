defmodule RegentsWeb.OnchainSteps do
  @moduledoc """
  The server half of a wallet-button component. `skills/onchain-buttons` has the
  rules; The Stake and Redeem components use it.

  The component builds a `RegentChain.Review` for the account's main wallet and
  hands it to `put_review/2`, which remembers it and pushes it to the page
  before anyone presses. The page reports each press against the review it sent from.
  Every sent step is then read at the latest block of the review's chain, every
  quarter second, until it lands or the page stops asking. Nothing is kept beyond
  the page. A step that lands asks every reader of its chain to read it again
  (`Regents.ChainRefresh`), so the shared figures show what it changed.

  Signed in, every review is built for the account's main wallet
  (`RegentsWeb.ShellLive.Identity.main_wallet/1`), and the page sends only from
  that wallet. Signed out there is no review.
  """

  use Phoenix.Component
  import Phoenix.LiveView, only: [push_event: 3, start_async: 3]

  alias RegentChain.{Outcome, Presses}
  alias Regents.{ChainClient, ChainRefresh}
  alias RegentsWeb.EventInput

  @recheck_ms 250
  @refusals ~w(wallet_declined switch_declined network_mismatch insufficient_funds)
  @address ~r/\A0x[0-9a-fA-F]{40}\z/

  @doc "The assigns a wallet-button component starts with."
  def init(socket), do: assign(socket, presses: Presses.new(), review: nil, press_note: nil)

  @doc "Privy's active wallet as the page reported it, lowercased, or `nil`."
  def active_wallet(%{"address" => address}) when is_binary(address) do
    if Regex.match?(@address, address), do: String.downcase(address)
  end

  def active_wallet(_params), do: nil

  @doc """
  Puts `review` (or none) on the page when it is not the one already there. A
  review is fixed once built, so a new signer, chain or figure is a new review,
  and the page drops the old one as soon as this arrives.
  """
  def put_review(socket, review) do
    if review_id(review) == review_id(socket.assigns.review) do
      socket
    else
      presses =
        if review,
          do: Presses.remember(socket.assigns.presses, review),
          else: socket.assigns.presses

      socket
      |> assign(review: review, presses: presses)
      |> push_event("onchain-steps:review", %{component_id: socket.assigns.id, review: review})
    end
  end

  @doc "The wallet sent a step; it is read from now on against the review it was sent from."
  def sent(socket, params) do
    case Presses.sent(socket.assigns.presses, params) do
      {:ok, entry, presses} ->
        socket |> assign(presses: presses, press_note: nil) |> check(entry)

      :error ->
        socket
    end
  end

  @doc """
  The wallet signed a step: `{:ok, signed, socket}` with the server's own typed
  data and the signature, for the component to hand on.
  """
  def signed(socket, params) do
    case Presses.signed(socket.assigns.presses, params) do
      {:ok, signed} -> {:ok, signed, assign(socket, press_note: nil)}
      :error -> :error
    end
  end

  @doc "Starts reading a step again after the page stopped on its own."
  def check_again(socket, hash) do
    case Presses.check_again(socket.assigns.presses, hash) do
      {nil, _presses} -> socket
      {entry, presses} -> socket |> assign(presses: presses) |> check(entry)
    end
  end

  @doc "One answer from `handle_async({:onchain_step, hash}, result, socket)`."
  def checked(socket, hash, result) do
    answer =
      case result do
        {:ok, answer} -> answer
        {:exit, _reason} -> :unanswered
      end

    case Presses.checked(socket.assigns.presses, hash, answer) do
      {nil, _presses} ->
        socket

      {entry, presses} ->
        socket = assign(socket, presses: presses)
        if entry.outcome == :confirmed, do: ChainRefresh.request(entry.review.chain.chain_id)
        if Presses.reading?(entry), do: check(socket, entry), else: socket
    end
  end

  @doc """
  What to say when a press sent nothing, or may have sent something, in words
  for the person who pressed, as parts for `note/1`. `main` is the signed-in
  account's main wallet (`nil` signed out) and `active` Privy's active wallet.
  """
  def failure_note(reason, main, active, chain_name)

  def failure_note(reason, nil, _active, _chain_name)
      when reason in ~w(step_unknown wallet_unavailable),
      do: ["Sign in to send this. Nothing was sent."]

  def failure_note(reason, main, nil, _chain_name)
      when reason in ~w(step_unknown wallet_unavailable),
      do: [
        "Connect ",
        {:address, main},
        ", your account's main wallet, then press again. Nothing was sent."
      ]

  def failure_note(reason, main, active, _chain_name)
      when reason in ~w(step_unknown wallet_unavailable) do
    cond do
      active != main ->
        mismatch_note(main, active) ++ [" Nothing was sent."]

      reason == "step_unknown" ->
        [
          "This can't be sent as it stands. Check the details above, then press again. Nothing was sent."
        ]

      true ->
        ["Your wallet changed during the press, so nothing was sent. Press again."]
    end
  end

  def failure_note("switch_declined", _main, _active, chain_name),
    do: ["Your wallet declined the switch to #{chain_name}. Nothing was sent."]

  def failure_note("network_mismatch", _main, _active, chain_name),
    do: [
      "Your wallet isn't on #{chain_name}. Change the network to #{chain_name} in your wallet app, then press again. Nothing was sent."
    ]

  def failure_note("wallet_declined", _main, _active, _chain_name),
    do: ["Your wallet declined this. Nothing was sent."]

  def failure_note("insufficient_funds", _main, _active, chain_name),
    do: [
      "Your wallet doesn't have enough on #{chain_name} to pay the network fee. Nothing was sent."
    ]

  def failure_note("send_unconfirmed", _main, _active, _chain_name),
    do: ["Your wallet may have sent this. Check your wallet activity."]

  @doc """
  The note beside the buttons for a press that failed for `reason`: its words,
  as parts for `note/1`, and whether the wallet turned the press down (it
  declined the step or the switch to the step's network, could not move there,
  or could not pay the fee), which the page answers with a shake.
  """
  def press_note(reason, parts), do: %{parts: parts, refused: reason in @refusals}

  @doc "The note beside the buttons for an event the panel could not read."
  def unreadable_note, do: %{parts: [EventInput.unreadable()], refused: false}

  @doc """
  The note beside the buttons while the wallet app has open a wallet other than
  the signed-in account's `main` one, naming both and asking the person to
  switch, as parts for `note/1`.
  """
  def mismatch_note(main, active) when is_binary(main) and is_binary(active) and main != active,
    do: [
      "Your wallet is on ",
      {:address, active},
      ". Switch to ",
      {:address, main},
      ", your account's main wallet."
    ]

  def mismatch_note(_main, _active), do: nil

  attr :id, :string, required: true

  attr :parts, :list,
    required: true,
    doc: "words, and `{:address, address}` for each wallet the note names"

  @doc """
  A note from `failure_note/4` or `mismatch_note/2`, or a step's title: its words,
  with each wallet it names opening and copying its full address
  (`Regent.Primitives.address`).
  """
  def note(assigns) do
    # Written on one line and left unformatted: a line break between the parts would
    # show as a space before the punctuation that follows an address.
    ~H"""
    <span id={@id} phx-no-format><%= for {part, index} <- Enum.with_index(@parts) do %><%= if is_binary(part) do %>{part}<% else %><Regent.Primitives.address id={"#{@id}-#{index}"} address={elem(part, 1)} /><% end %><% end %></span>
    """
  end

  attr :id, :string, required: true, doc: "the press note's id"
  attr :press, :map, default: nil, doc: "a `press_note/2`, or `nil` while there is none"
  attr :lost, :boolean, default: false, doc: "whether the page's lost-connection line is here"

  @doc """
  The note for the last press that was not sent, and the lost-connection line
  when the page has one. They float where the page places `.onchain-notes`, so
  their coming and going moves nothing. A note the wallet turned down shakes, and
  a note that goes fades out from the layer kept beside it (`MotionNote`).
  """
  def notes(assigns) do
    ~H"""
    <div class="onchain-notes">
      <p
        :if={@press}
        id={@id}
        class="onchain-note"
        role="alert"
        phx-hook="MotionNote"
        data-refused={@press.refused}
      >
        <.note id={"#{@id}-words"} parts={@press.parts} />
      </p>
      <p :if={@lost} id={"#{@id}-lost"} class="onchain-note" role="status" data-onchain-lost hidden>
        Connection lost, so nothing was sent. Press again once it's back.
      </p>
      <div id={"#{@id}-leaving"} class="onchain-notes__leaving" phx-update="ignore"></div>
    </div>
    """
  end

  @doc """
  One sent step as the page shows it: its state and generic words. A component
  names its steps and may say more about them.
  """
  def describe(entry, chain_name) do
    state = if Presses.stalled?(entry), do: :stalled, else: entry.outcome
    %{hash: entry.hash, state: state, words: words(state, chain_name)}
  end

  @doc """
  Whether a step named in `names` was sent and is still being read, for the
  button that sends them to say "Confirming". It never stops a press.
  """
  def confirming?(presses, names),
    do: Enum.any?(presses.sent, &(&1.name in names and Presses.reading?(&1)))

  defp words(:pending, chain_name), do: "Sent. Waiting for #{chain_name}."

  defp words(:stalled, chain_name),
    do: "#{chain_name} has not confirmed this yet. Check again, or look in your wallet activity."

  defp words(:confirmed, _chain_name), do: "Done."
  defp words(:reverted, _chain_name), do: "This did not go through and nothing moved."

  defp words(_not_this_step, _chain_name),
    do:
      "This transaction is not the one this page prepared, so it can't be followed here. Check it in your wallet activity."

  defp check(socket, %{step: nil}), do: socket

  defp check(socket, %{hash: hash, reads: reads, review: review, step: step}) do
    start_async(socket, {:onchain_step, hash}, fn ->
      if reads > 0, do: Process.sleep(@recheck_ms)
      Outcome.of(ChainClient, review, step, hash)
    end)
  end

  defp review_id(nil), do: nil
  defp review_id(%{id: id}), do: id
end
