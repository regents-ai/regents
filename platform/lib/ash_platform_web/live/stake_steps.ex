defmodule AshPlatformWeb.StakeSteps do
  @moduledoc """
  The Stake page's wallet steps, on the page's side.

  The review for what is on screen is pushed before anyone presses. The browser
  reports only what the wallet said about a press, and every sent step is then
  read on Base at the latest block until it lands or the page stops asking. Every
  word a person reads about a press is written here.
  """

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [push_event: 3, start_async: 3]

  alias AshPlatform.Staking
  alias AshPlatform.Staking.{ChainClient, Steps}
  alias RegentChain.Outcome

  @component "regent-staking"
  @recheck_ms 2_000
  @recheck_limit 90
  # Steps built for earlier reviews stay checkable for a while after the page has
  # moved on, so a press made just before a keystroke is still recognised.
  @built_limit 32
  @shown_limit 8
  @failures ~w(step_unknown wallet_unavailable network_mismatch wallet_declined insufficient_funds send_unconfirmed)
  @hash ~r/^0x[0-9a-fA-F]{64}$/

  @blank_form %{for_other: false, receiver: "", acknowledged: nil}

  def assigns,
    do: [
      staking_form: @blank_form,
      staking_review: nil,
      staking_built: [],
      staking_sent: [],
      staking_press: nil
    ]

  def blank_form, do: @blank_form

  @doc "Forgets the review on the page, so the next `sync/2` pushes it again."
  def forget_review(socket), do: assign(socket, staking_review: nil)

  @doc """
  Builds the review for `signer` from what is on screen and pushes it when it
  changed. Without a signer there is no review: the buttons ask for sign-in.
  """
  def sync(socket, nil), do: assign(socket, staking_review: nil)

  def sync(socket, signer) do
    review = Steps.review(@component, signer, socket.assigns.staking, form(socket.assigns))

    if review == socket.assigns.staking_review do
      socket
    else
      built =
        review.steps
        |> Enum.map(&%{signer: review.signer, step: &1, inputs: review.inputs})
        |> Kernel.++(socket.assigns.staking_built)
        |> Enum.uniq_by(&{&1.signer, &1.step})
        |> Enum.take(@built_limit)

      socket
      |> assign(staking_review: review, staking_built: built)
      |> push_event("onchain-steps:review", review)
    end
  end

  @doc """
  A press made before the review caught up with the form. The form is taken as
  the page's own and the review rebuilt; the reply carries it and names the step
  the button now stands for, so the browser sends it at once. Signed out there
  is no review, and the reply is empty.
  """
  def prepare_and_send(socket, signer, form) do
    socket = socket |> apply_form(form) |> sync(signer)

    case socket.assigns.staking_review do
      nil -> {%{}, socket}
      review -> {%{review: review, send: next_step(socket.assigns)}, socket}
    end
  end

  @doc """
  The receiver fields as they now stand. Ticking the warning acknowledges
  exactly the address shown; any change to the address or to the choice to
  stake for someone else takes that acknowledgment back.
  """
  def change_form(form, params) do
    receiver = text(Map.get(params, "receiver", form.receiver))
    for_other = params["for_other"] == "true"

    acknowledged =
      cond do
        params["_target"] == ["acknowledged"] -> acknowledge(params["acknowledged"], receiver)
        receiver != form.receiver or for_other != form.for_other -> nil
        true -> form.acknowledged
      end

    %{for_other: for_other, receiver: receiver, acknowledged: acknowledged}
  end

  @doc "Takes back an acknowledgment, as a new action or a new wallet does."
  def unacknowledge(socket),
    do: assign(socket, staking_form: %{socket.assigns.staking_form | acknowledged: nil})

  @doc """
  The wallet sent a step. It is read on Base from now on, against the step built
  for the wallet that sent it.
  """
  def sent(socket, %{"step" => name, "transaction_hash" => hash, "data" => data, "from" => from})
      when is_binary(name) and is_binary(hash) and is_binary(data) and is_binary(from) do
    if Regex.match?(@hash, hash) do
      hash = String.downcase(hash)
      from = String.downcase(from)

      built =
        Enum.find(
          socket.assigns.staking_built,
          &(&1.signer == from and &1.step.step == name and &1.step.data == data)
        )

      entry = %{hash: hash, name: name, built: built, outcome: :pending, reads: 0, limit: nil}

      socket
      |> assign(staking_press: nil)
      |> put_entry(entry)
      |> check(entry)
    else
      socket
    end
  end

  def sent(socket, _params), do: socket

  @doc "Nothing was sent, or the wallet may have sent it; the reason picks the words."
  def failed(socket, %{"step" => name, "reason" => reason})
      when is_binary(name) and reason in @failures,
      do: assign(socket, staking_press: failure_copy(reason, name, socket.assigns))

  def failed(socket, _params), do: socket

  @doc "Asks Base about a step again after the page stopped asking on its own."
  def check_again(socket, hash) do
    case entry(socket, hash) do
      %{built: %{}} = entry ->
        entry = %{entry | outcome: :pending, reads: 0, limit: nil}
        socket |> put_entry(entry) |> check(entry)

      _unknown ->
        socket
    end
  end

  @doc """
  One answer from Base about a sent step, with the outcome it settled on, or
  `nil` when the page has since let that step go.
  """
  def checked(socket, hash, result) do
    case entry(socket, hash) do
      nil ->
        {nil, socket}

      entry ->
        outcome = outcome(result)

        entry = %{
          entry
          | outcome: outcome,
            reads: entry.reads + 1,
            limit: if(outcome == :reverted, do: contract_limit(entry, socket.assigns.staking))
        }

        socket = put_entry(socket, entry)

        if entry.outcome == :pending and entry.reads < @recheck_limit,
          do: {:pending, check(socket, entry)},
          else: {entry.outcome, socket}
    end
  end

  @doc """
  The step the primary button sends: the approval while one is needed and none
  from this wallet is still on its way to Base, then the action itself. Once an
  approval lands, the wallet is read again and that reading says whether another
  is needed; one Base has stopped being asked about is on its way no longer.
  """
  def next_step(%{staking_review: nil, staking_action: action}), do: action

  def next_step(%{staking_review: review, staking_action: action, staking_sent: sent}) do
    case Steps.find(review, "approve") do
      nil -> action
      approval -> if approval_sent?(sent, review.signer, approval), do: action, else: "approve"
    end
  end

  @doc "What the approval note beside the primary button says, if anything."
  def approval_note(%{staking_review: nil}), do: nil

  def approval_note(%{staking_review: review} = assigns) do
    cond do
      is_nil(Steps.find(review, "approve")) ->
        nil

      next_step(assigns) == "approve" ->
        "Staking this amount needs an exact REGENT approval first. Approve it, then stake."

      true ->
        "Approval sent. You can stake now; if the approval has not landed yet, the stake will not go through."
    end
  end

  @doc """
  Each sent step as the page shows it, newest first. A stake Base turned down
  says so when the reading at the time showed staking paused or full.
  """
  def shown(sent), do: Enum.map(sent, &describe/1)

  defp form(assigns),
    do:
      Map.merge(assigns.staking_form, %{
        action: assigns.staking_action,
        amount: assigns.staking_amount
      })

  defp apply_form(socket, %{} = form) do
    current = socket.assigns.staking_form
    receiver = text(form["receiver"])

    acknowledged =
      if form["acknowledged"] == true and receiver == current.receiver,
        do: current.acknowledged

    socket
    |> assign(
      staking_action:
        if(form["action"] in ~w(stake unstake),
          do: form["action"],
          else: socket.assigns.staking_action
        ),
      staking_amount: text(form["amount"]),
      staking_form: %{
        for_other: form["for_other"] == true,
        receiver: receiver,
        acknowledged: acknowledged
      }
    )
  end

  defp apply_form(socket, _form), do: socket

  defp text(value) when is_binary(value), do: value
  defp text(_value), do: ""

  defp acknowledge("true", receiver) do
    case Steps.other_address(receiver) do
      :error -> nil
      address -> address
    end
  end

  defp acknowledge(_unticked, _receiver), do: nil

  defp approval_sent?(sent, signer, approval),
    do:
      Enum.any?(
        sent,
        &(match?(%{signer: ^signer, step: ^approval}, &1.built) and &1.outcome == :pending and
            &1.reads < @recheck_limit)
      )

  defp check(socket, %{built: nil}), do: socket

  defp check(socket, %{hash: hash, reads: reads, built: %{signer: signer, step: step}}) do
    client = ChainClient.module()

    start_async(socket, {:staking_step, hash}, fn ->
      if reads > 0, do: Process.sleep(@recheck_ms)
      Outcome.of(client, hash, signer, step)
    end)
  end

  # A read that failed is no answer about the step, so it is read again.
  defp outcome({:ok, {:ok, outcome}}), do: outcome
  defp outcome({:ok, {:error, :not_this_step}}), do: :not_this_step
  defp outcome(_unanswered), do: :pending

  defp entry(socket, hash), do: Enum.find(socket.assigns.staking_sent, &(&1.hash == hash))

  defp put_entry(socket, entry) do
    sent =
      case Enum.find_index(socket.assigns.staking_sent, &(&1.hash == entry.hash)) do
        nil -> Enum.take([entry | socket.assigns.staking_sent], @shown_limit)
        index -> List.replace_at(socket.assigns.staking_sent, index, entry)
      end

    assign(socket, staking_sent: sent)
  end

  defp describe(%{
         hash: hash,
         name: name,
         built: built,
         outcome: outcome,
         reads: reads,
         limit: limit
       }) do
    %{
      hash: hash,
      title: title(name, built),
      outcome: if(outcome == :pending and reads >= @recheck_limit, do: :stalled, else: outcome),
      words:
        turned_down(outcome, limit) ||
          words(if(built, do: outcome, else: :not_this_step), name, built, reads),
      href: "https://basescan.org/tx/#{hash}"
    }
  end

  # Only a stake, or a claim that restakes, is refused while staking is paused
  # or would take the contract past what it can hold.
  defp contract_limit(%{name: "claim_and_restake_regent"}, %{} = staking),
    do: Staking.limit_refusal(staking, "claim_and_restake_regent", nil)

  defp contract_limit(%{name: "stake", built: %{inputs: %{amount: amount}}}, %{} = staking) do
    {:ok, raw} = Staking.parse_amount(amount)
    Staking.limit_refusal(staking, "stake", raw)
  end

  defp contract_limit(_entry, _staking), do: nil

  defp turned_down(:reverted, :staking_paused),
    do: "Staking is paused on Base right now, so this did not go through and nothing moved."

  defp turned_down(:reverted, :amount_above_capacity),
    do:
      "The staking contract cannot take that much more REGENT, so this did not go through and nothing moved."

  defp turned_down(_outcome, _limit), do: nil

  defp title("approve", _built), do: "REGENT approval"

  defp title("stake", %{inputs: %{for_other: true, receiver: receiver}} = built),
    do: "Stake #{amount(built)} REGENT for #{RegentFormat.short_wallet(String.trim(receiver))}"

  defp title("stake", built), do: "Stake #{amount(built)} REGENT"
  defp title("unstake", built), do: "Unstake #{amount(built)} REGENT"
  defp title("claim_usdc", _built), do: "USDC claim"
  defp title("claim_regent", _built), do: "REGENT claim"
  defp title("claim_and_restake_regent", _built), do: "Claim and restake"
  defp title(_name, _built), do: "Transaction"

  defp amount(%{inputs: %{amount: amount}}), do: String.trim(amount)
  defp amount(nil), do: ""

  defp words(:pending, _name, _built, reads) when reads >= @recheck_limit,
    do: "Base has not confirmed this yet. Follow it on BaseScan or check again."

  defp words(:pending, _name, _built, _reads), do: "Sent. Waiting for Base."
  defp words(:confirmed, "approve", _built, _reads), do: "Approved. You can stake now."

  defp words(:confirmed, "stake", %{inputs: %{for_other: true}}, _reads),
    do: "Done. The receiving address owns this stake."

  defp words(:confirmed, "stake", _built, _reads), do: "Done. Your position is updating."

  defp words(:confirmed, "unstake", _built, _reads),
    do: "Done. The REGENT is back in your wallet."

  defp words(:confirmed, "claim_usdc", _built, _reads),
    do: "Done. Your USDC rewards were claimed."

  defp words(:confirmed, "claim_regent", _built, _reads),
    do: "Done. Your REGENT rewards were claimed."

  defp words(:confirmed, "claim_and_restake_regent", _built, _reads),
    do: "Done. Your REGENT rewards were added to your stake."

  defp words(:reverted, "approve", _built, _reads),
    do: "The approval did not go through and nothing moved. Press Approve REGENT again."

  defp words(:reverted, "stake", _built, _reads),
    do:
      "The stake did not go through and nothing moved. This usually means the approval had not landed yet, or the amount is more than the wallet holds. Check both, then press Stake REGENT again."

  defp words(:reverted, "unstake", _built, _reads),
    do:
      "The unstake did not go through and nothing moved. Check the amount is not more than you have staked, then try again."

  defp words(:reverted, "claim_usdc", _built, _reads),
    do: "The claim did not go through and nothing moved. There may be no USDC to claim yet."

  defp words(:reverted, "claim_regent", _built, _reads),
    do:
      "The claim did not go through and nothing moved. There may be no REGENT rewards to claim yet, or not enough in the reward pool."

  defp words(:reverted, "claim_and_restake_regent", _built, _reads),
    do:
      "The claim did not go through and nothing moved. There may be no REGENT rewards to restake yet, or staking may be paused."

  defp words(_not_this_step, _name, _built, _reads),
    do:
      "This transaction is not the one this page prepared, so it cannot be followed here. Check it in your wallet activity."

  # A press with no step behind it says what on the form is missing.
  defp failure_copy("step_unknown", name, assigns) when name in ~w(approve stake unstake) do
    form = form(assigns)

    case {Staking.parse_amount(form.amount), name, Steps.receiver(form)} do
      {{:error, _invalid}, _name, _receiver} ->
        "Enter an amount in REGENT above zero. Nothing was sent."

      {_amount, "unstake", _receiver} ->
        "This page is out of date. Refresh it and press again."

      {_amount, _name, {:error, :receiver_invalid}} ->
        "Enter a valid receiving address. Nothing was sent."

      {_amount, _name, {:error, :receiver_unacknowledged}} ->
        "Tick the warning about the receiving address first. Nothing was sent."

      _built ->
        "This page is out of date. Refresh it and press again."
    end
  end

  defp failure_copy("step_unknown", _name, _assigns),
    do: "This page is out of date. Refresh it and press again."

  defp failure_copy("wallet_unavailable", _name, _assigns),
    do: "Nothing was sent. Select a wallet on your account in your wallet app, then press again."

  defp failure_copy("network_mismatch", _name, _assigns),
    do:
      "Your wallet is on a different network. Switch it to Base, then try again. Nothing was sent."

  defp failure_copy("wallet_declined", _name, _assigns),
    do: "Your wallet declined this. Nothing was sent."

  defp failure_copy("insufficient_funds", _name, _assigns),
    do:
      "Your wallet does not have enough ETH on Base to pay the network fee. Nothing was sent. Add a little ETH on Base, then press again."

  defp failure_copy("send_unconfirmed", _name, _assigns),
    do: "Your wallet may have sent this. Check your wallet activity."
end
