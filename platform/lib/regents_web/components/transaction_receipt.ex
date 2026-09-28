defmodule RegentsWeb.Components.TransactionReceipt do
  @moduledoc """
  The pop-up a wallet step opens once Base has confirmed it: what happened,
  where the wallet stands now, read again after it, and the transaction on
  BaseScan. It opens as it arrives and sends `close_event` to whatever drew it
  when the reader closes it.
  """
  use Phoenix.Component
  alias RegentsWeb.TokenDisplay

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :summary, :string, required: true
  attr :hash, :string, required: true
  attr :close_event, :string, required: true

  attr :position, :any,
    required: true,
    doc: "`:reading`, `:unavailable` or the wallet's figures read after the step"

  attr :figures, :list, required: true, doc: "`%{label, key, unit}` for each figure shown"

  def receipt(assigns) do
    ~H"""
    <dialog
      id={@id}
      class="transaction-receipt"
      aria-labelledby={"#{@id}-heading"}
      phx-hook="InfoDialog"
      data-open
      data-close-event={@close_event}
    >
      <p class="transaction-receipt__kicker">Base transaction receipt</p>
      <h2 id={"#{@id}-heading"}>{@title}</h2>
      <p class="transaction-receipt__summary">{@summary}</p>
      <dl>
        <div :for={figure <- @figures}>
          <dt>{figure.label}</dt>
          <dd><.figure position={@position} key={figure.key} unit={figure.unit} /></dd>
        </div>
        <div>
          <dt>Transaction</dt>
          <dd>
            <a href={"https://basescan.org/tx/#{@hash}"} target="_blank" rel="noopener noreferrer">
              View on BaseScan <span aria-hidden="true">↗</span>
            </a>
          </dd>
        </div>
      </dl>
      <form method="dialog">
        <Regent.Primitives.button variant="secondary" type="submit" value="close">Done</Regent.Primitives.button>
      </form>
    </dialog>
    """
  end

  attr :position, :any, required: true
  attr :key, :atom, required: true
  attr :unit, :string, required: true

  defp figure(%{position: :reading} = assigns), do: ~H"Reading from Base…"
  defp figure(%{position: :unavailable} = assigns), do: ~H"Could not be read just now"

  defp figure(assigns),
    do: ~H"<TokenDisplay.amount amount={Map.fetch!(@position, @key)} unit={@unit} />"
end
