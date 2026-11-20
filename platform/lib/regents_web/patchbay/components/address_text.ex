defmodule RegentsWeb.Patchbay.AddressText do
  @moduledoc """
  HTML rendered from Patchbay's own markdown, with each full `0x` address in it
  drawn by `Regent.Primitives.address` (`Regents.Patchbay.AddressText` cuts them out).
  """

  use Phoenix.Component

  @doc """
  The pieces in order: HTML as it was rendered, and each address as the shared
  address piece, numbered after `id`.
  """
  attr :id, :string, required: true
  attr :pieces, :list, required: true, doc: "`Regents.Patchbay.AddressText.html/1`."

  def address_text(assigns) do
    assigns = assign(assigns, :numbered, Enum.with_index(assigns.pieces))

    ~H"""
    <.piece :for={{piece, n} <- @numbered} id={"#{@id}-#{n}"} piece={piece} />
    """
  end

  attr :id, :string, required: true
  attr :piece, :any, required: true

  defp piece(%{piece: {:address, address}} = assigns) do
    assigns = assign(assigns, :address, address)

    ~H"""
    <Regent.Primitives.address id={@id} address={@address} />
    """
  end

  # HTML pieces come only from `Regents.Patchbay.AddressText.html/1`, which renders
  # Patchbay's own committed markdown with raw HTML and scriptable links stripped.
  # sobelow_skip ["XSS.Raw"]
  defp piece(%{piece: {:html, html}} = assigns) do
    assigns = assign(assigns, :html, Phoenix.HTML.raw(html))

    ~H"""
    {@html}
    """
  end
end
