defmodule RegentsWeb.Keyfleet.Components.KeyCard do
  @moduledoc """
  A Key's card: the picture its metadata names, as a wallet or marketplace
  shows it, or the Interim Keyfleet Access Pass until the Key's own card is
  drawn. Under a mouse it turns a little toward the pointer and a light
  crosses its foil (`KeyCardTurn`); a finger, a keyboard or less motion gets
  the card as it is.
  """
  use RegentsWeb, :html

  attr :id, :string, required: true
  attr :src, :string, required: true
  attr :alt, :string, required: true
  attr :class, :any, default: nil

  def card(assigns) do
    ~H"""
    <div id={@id} class={["key-card", @class]} phx-hook="KeyCardTurn">
      <div class="key-card__tilt" data-key-tilt>
        <img id={"#{@id}-picture"} src={@src} alt={@alt} fetchpriority="high" />
        <span class="key-card__light" data-key-light aria-hidden="true"></span>
      </div>
    </div>
    """
  end
end
