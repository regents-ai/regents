defmodule AshPlatformWeb.Components.Background do
  @moduledoc "Inert compatibility seam. Technical artwork belongs in bounded figures."
  use Phoenix.Component

  attr(:slot, :any, required: true)

  def background(assigns) do
    ~H"""
    """
  end
end
