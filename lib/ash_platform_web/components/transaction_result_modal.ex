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
  Hands finished results to the LiveView that owns the queue, in step order.

  A wallet LiveComponent runs inside that process, so this is the root's own
  message; anything that is not a result is not reported.
  """
  def report(results),
    do: results |> Enum.reject(&is_nil/1) |> Enum.each(&send(self(), {:transaction_result, &1}))

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
