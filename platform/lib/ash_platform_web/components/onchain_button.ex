defmodule AshPlatformWeb.Components.OnchainButton do
  @moduledoc """
  The words inside a wallet button. They say "Sign tx in wallet" while the wallet
  has one of its presses (marked in the browser) and "Confirming" while a
  transaction it sent is still being read on Base (`data-confirming`, from the
  server). The button itself keeps taking presses in every state.
  """
  use Phoenix.Component

  attr :label, :string, required: true

  def label(assigns) do
    ~H"""
    <span data-press-label>{@label}</span><span data-wallet-wait><span
      class="onchain-spinner"
      aria-hidden="true"
    ></span>Sign tx in wallet</span><span data-confirming-label><span
      class="onchain-spinner"
      aria-hidden="true"
    ></span>Confirming</span>
    """
  end
end
