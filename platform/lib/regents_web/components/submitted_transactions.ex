defmodule RegentsWeb.Components.SubmittedTransactions do
  @moduledoc """
  The transactions a wallet button sent, newest first, each in its own box with
  what Base says about it and its link on BaseScan. Nothing shows until the
  wallet has sent one.
  """
  use Phoenix.Component

  attr :id, :string, required: true, doc: "each transaction's box is `\#{id}-\#{hash}`"
  attr :sent, :list, required: true
  attr :myself, :any, required: true

  def list(assigns) do
    ~H"""
    <div :if={@sent != []} class="submitted-transactions">
      <h3 id={"#{@id}-heading"} class="submitted-transactions__title">Submitted Transactions</h3>
      <ol aria-labelledby={"#{@id}-heading"} aria-live="polite">
        <li :for={entry <- @sent} id={"#{@id}-#{entry.hash}"} data-outcome={entry.state}>
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
    </div>
    """
  end
end
