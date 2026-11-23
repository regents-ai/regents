defmodule RegentsWeb.Autolaunch.Components.TokenLinks do
  @moduledoc false
  use Phoenix.Component

  alias Regents.Autolaunch.Lab
  alias RegentsWeb.Stake.TokenLinks, as: SharedTokenLinks

  @doc "The REGENT contract address a visitor copies. Same token the buy link names."
  defdelegate address, to: SharedTokenLinks

  defdelegate buy, to: SharedTokenLinks
  defdelegate chart, to: SharedTokenLinks

  # Both destinations are public Base mainnet. On a local-fork site they are
  # named as such, because nothing they sell or show is the fork's REGENT. The
  # links carry their own ids: the top bar's REGENT menu, on the same page,
  # already uses regent-buy and regent-chart.
  def regent_market_links(assigns) do
    assigns = assign(assigns, :local_lab?, Lab.test_chain?())

    ~H"""
    <nav class="regent-token-links" aria-label="REGENT market">
      <a
        class="rg-button rg-button--secondary"
        href={buy()}
        id="regent-market-buy"
        target="_blank"
        rel="noopener noreferrer"
      >
        Buy REGENT{mainnet_suffix(@local_lab?)}
      </a>
      <a
        class="rg-button rg-button--secondary"
        href={chart()}
        id="regent-market-chart"
        target="_blank"
        rel="noopener noreferrer"
      >
        View REGENT Chart{mainnet_suffix(@local_lab?)}
      </a>
      <p :if={@local_lab?} class="regent-token-links__note">
        Both open public Base mainnet. This fork's test REGENT cannot be bought there.
      </p>
    </nav>
    """
  end

  defp mainnet_suffix(true), do: " · Base mainnet"
  defp mainnet_suffix(false), do: ""
end
