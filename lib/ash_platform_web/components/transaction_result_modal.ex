defmodule AshPlatformWeb.Components.TransactionResultModal do
  @moduledoc """
  The one dialog every wallet surface reports a finished transaction through.

  A result exists only where the server has already classified the exact bound
  hash: confirmed, reverted, or mined without recording the reviewed action. The
  browser may show and dismiss one; it never supplies a status, a hash, a link,
  or a sentence of its own.
  """

  use Phoenix.Component

  alias AshPlatform.WalletActions.Rpc

  @doc """
  One result for one server-classified terminal transaction, or nothing at all
  when its bound hash is not an exact transaction hash.

  The id is the operation, its step, that classification and the exact hash, so
  a repeated callback, a verification retry or a rerender describes the result
  already queued rather than a new one.
  """
  def result(%{
        status: status,
        action_id: action_id,
        step: step,
        hash: hash,
        label: label,
        message: message
      }) do
    if Rpc.valid_hash?(hash) do
      %{
        id: Enum.join([action_id, step, status, hash], ":"),
        status: status,
        title: title(status),
        label: label,
        message: message,
        transaction_hash: hash
      }
    end
  end

  defp title(:confirmed), do: "Transaction confirmed"
  defp title(:reverted), do: "Transaction reverted"
  defp title(:unverified), do: "Transaction not verified"

  @doc """
  Hands one live operation transition to the LiveView that owns the queue.

  A socket that was elsewhere while the customer signed may find several ordered
  steps crossed at once, and each allowance the server verified along the way is
  a transaction of its own. Every step between the one this socket last watched
  and the one now in front of the customer is confirmed by `confirmed_step`, in
  order, ahead of the operation's own `current_result`.

  A restored or repeated terminal operation was never watched moving, so it
  reports nothing at all.
  """
  def report_transition(prior, returned, ordered_steps, confirmed_step, current_result)

  def report_transition(
        %{action_id: id, step: from, terminal_at: nil},
        %{action_id: id, step: to},
        ordered_steps,
        confirmed_step,
        current_result
      ) do
    ordered_steps
    |> Enum.drop_while(&(&1 != to_string(from)))
    |> Enum.take_while(&(&1 != to_string(to)))
    |> Enum.map(confirmed_step)
    |> Enum.concat([current_result])
    |> report()
  end

  def report_transition(_prior, _returned, _ordered_steps, _confirmed_step, _current_result),
    do: :ok

  # A wallet LiveComponent runs inside the root LiveView's process, so this is
  # that process's own message. The queue is what decides whether a result is
  # new, and what nothing at all means.
  defp report(results), do: Enum.each(results, &send(self(), {:transaction_result, &1}))

  @doc """
  The one sentence a verified transaction says, wherever it is reported.

  Whatever a surface reads back afterwards is separate and may be pending,
  succeed, fail, or exit, so this claims only the receipt.
  """
  def confirmed_copy, do: "Confirmed on Base."

  @doc "The Base explorer link for an exact transaction hash, or nothing at all."
  def explorer_url(hash) do
    if Rpc.valid_hash?(hash), do: "https://basescan.org/tx/" <> hash
  end

  attr :result, :map, default: nil

  @doc """
  The native dialog, teleported to `body` so no shell scroller, stacking context
  or mobile `inert` boundary can trap it. The server owns its content; the hook
  owns only whether it is natively open.
  """
  def transaction_result(assigns) do
    assigns =
      assign(assigns, :url, assigns.result && explorer_url(assigns.result.transaction_hash))

    ~H"""
    <.portal id="transaction-result-portal" target="body">
      <dialog
        id="transaction-result-dialog"
        class="transaction-result"
        phx-hook="TransactionResultModal"
        data-result-id={@result && @result.id}
        aria-labelledby="transaction-result-title"
      >
        <article :if={@result} class="transaction-result-body" data-status={@result.status}>
          <p class="transaction-result-label">{@result.label}</p>
          <h2 id="transaction-result-title">{@result.title}</h2>
          <p class="transaction-result-message">{@result.message}</p>
          <div class="transaction-result-controls">
            <a :if={@url} href={@url} target="_blank" rel="noopener">View on BaseScan</a>
            <button type="button" data-transaction-result-close>Close</button>
          </div>
        </article>
      </dialog>
    </.portal>
    """
  end
end
