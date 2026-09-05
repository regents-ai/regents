defmodule AshPlatformWeb.SettingsLive do
  @moduledoc false

  use AshPlatformWeb, :html

  import AshPlatformWeb.Components.VerifiedConnections

  attr(:verified_connections, :list, default: [])
  attr(:verified_connections_notice, :map, default: nil)
  attr(:rest, :global)

  def page(assigns) do
    ~H"""
    <article class="settings-page" {@rest}>
      <header class="settings-page__header">
        <h1>Settings</h1>
      </header>

      <.verified_connections
        id="settings-verified-connections"
        class="settings-section"
        identities={@verified_connections}
        notice={@verified_connections_notice}
      />
    </article>
    """
  end
end
