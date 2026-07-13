defmodule AshPlatformWeb.Components.Shell.ContentFrame do
  @moduledoc false

  use Phoenix.Component

  attr(:content_status, :atom, required: true)
  slot(:content, required: true)

  def content_frame(assigns) do
    ~H"""
    <div id="app-shell-scroller" class="app-shell-scroller" tabindex="-1">
      <main id="route-content" aria-busy={to_string(@content_status == :loading)}>
        {render_slot(@content)}
      </main>
    </div>
    """
  end
end
