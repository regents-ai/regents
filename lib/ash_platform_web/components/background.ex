defmodule AshPlatformWeb.Components.Background do
  @moduledoc "Decorative presentation for canonical shell background slots."

  use Phoenix.Component

  @sources %{home: "/images/backgrounds/home.svg"}

  attr(:slot, :any, required: true)

  def background(assigns) do
    assigns = assign(assigns, :source, Map.get(@sources, assigns.slot))

    assigns =
      if assigns.source,
        do: assign(assigns, :source_style, ~s|--shell-background-mask: url("#{assigns.source}")|),
        else: assigns

    ~H"""
    <div
      :if={@source}
      class="shell-background"
      data-background-slot={@slot}
      data-motion-background
      aria-hidden="true"
    >
      <span class="shell-background__asset" style={@source_style}></span>
    </div>
    """
  end
end
