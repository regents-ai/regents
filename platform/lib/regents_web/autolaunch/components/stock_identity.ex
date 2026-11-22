defmodule RegentsWeb.Autolaunch.Components.StockIdentity do
  @moduledoc """
  A stock token's identity, in the same words wherever the site names one: its
  issuer, its chain and its exact contract address through
  `Regent.Primitives.address` (short form, copy icon, explorer arrow). A
  ticker or a company's name never names a stock token alone: each issuer has
  its own token for the same company, and neither is the share.

  The issuer is `Regents.Autolaunch.Stocks.Assets.issuer/1`'s, the chain's own.
  Base's stock tokens only, so far: Robinhood's come with Robinhood's pages.
  """
  use Phoenix.Component

  attr :chain, :atom, required: true, values: [:base]
  attr :address, :string, required: true, doc: "the token's contract address"
  attr :id, :string, required: true, doc: "the address piece's id"

  attr :explorer, :string,
    required: true,
    doc: "the chain `Regent.Primitives.address` opens the address on"

  @doc "The issuer and chain, then the address."
  def stock_identity(assigns) do
    ~H"""
    <span class="stock-identity">
      <span class="stock-identity__words">{words(@chain)}</span>
      <Regent.Primitives.address id={@id} address={@address} chain={@explorer} />
    </span>
    """
  end

  @doc "The issuer and chain in a few words, as `Coinbase token · Base`."
  @spec words(:base) :: String.t()
  def words(chain),
    do: "#{Regents.Autolaunch.Stocks.Assets.issuer(chain)} token · #{chain_name(chain)}"

  defp chain_name(:base), do: "Base"
end
