defmodule RegentsWeb.Autolaunch.Components.Loading do
  @moduledoc """
  What a page shows while it is still reading something after it opened: the
  shape of what is coming, in the site's one card, so nothing jumps when it
  arrives. Screen readers hear what is being read; the blocks are hidden from
  them. The look is `.loading-card` and `.loading-block` in
  `assets/css/autolaunch/components/surfaces.css`.
  """
  use Phoenix.Component

  attr :label, :string,
    required: true,
    doc: ~s(What is being read, as a screen reader hears it, such as "Reading the token".)

  attr :id, :string, default: nil

  @doc "Lines of text in one card."
  def placeholder(assigns) do
    ~H"""
    <div id={@id} class="loading-card" role="status">
      <span class="visually-hidden">{@label}</span>
      <span class="loading-block loading-card__title" aria-hidden="true"></span>
      <span :for={_line <- 1..3} class="loading-block loading-card__line" aria-hidden="true"></span>
    </div>
    """
  end
end
