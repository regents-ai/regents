defmodule AshPlatformWeb.Components.Background do
  @moduledoc "Stable presentation seam for founder-supplied shell backgrounds."

  use Phoenix.Component

  attr(:slot, :atom, required: true)

  def background(assigns) do
    ~H"""
    <div
      id="shell-background"
      class="shell-background"
      data-background-slot={@slot}
      data-background-state="neutral"
      aria-hidden="true"
    >
    </div>
    """
  end
end
