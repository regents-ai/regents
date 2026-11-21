defmodule RegentsWeb.Techtree.Components.BookCall do
  @moduledoc """
  The Book Call button: the header, the home page and every service's page
  show this one. It opens the booking page set in `TECHTREE_BOOK_CALL_URL`
  (`config/runtime.exs`) in a new tab. With no address set it is not shown at
  all.
  """

  use Phoenix.Component

  @doc "The booking page's address, or nil when none is set."
  @spec address() :: String.t() | nil
  def address, do: Application.get_env(:regents, :techtree_book_call)

  attr :variant, :atom, values: [:primary, :secondary], default: :primary
  attr :class, :any, default: nil
  attr :says_new_tab, :boolean, default: false, doc: "read aloud after the name: it opens in a new tab"
  attr :rest, :global

  def book_call(assigns) do
    assigns = assign(assigns, :address, address())

    ~H"""
    <a
      :if={@address}
      class={["rg-button", "rg-button--#{@variant}", @class]}
      href={@address}
      target="_blank"
      rel="noopener"
      {@rest}
    >
      Book Call<span :if={@says_new_tab} class="visually-hidden">, opens in a new tab</span>
    </a>
    """
  end
end
