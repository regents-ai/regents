defmodule AshPlatformWeb.SettingsLive do
  @moduledoc false

  use AshPlatformWeb, :html

  import AshPlatformWeb.Components.VerifiedConnections
  import AshPlatformWeb.Components.XConnections

  attr(:verified_connections, :list, default: [])
  attr(:verified_connections_notice, :map, default: nil)
  attr(:x_connections, :list, default: [])
  attr(:x_oauth_enabled, :boolean, default: false)
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

      <.x_connections
        id="settings-x-connections"
        class="settings-section"
        connections={@x_connections}
        enabled={@x_oauth_enabled}
      />

      <section class="settings-section" aria-labelledby="appearance-heading">
        <div>
          <h2 id="appearance-heading">Appearance</h2>
          <p>Choose how Regent looks on this device.</p>
        </div>

        <div class="settings-theme-choice" role="group" aria-label="Appearance">
          <button type="button" data-theme-choice="system">System</button>
          <button type="button" data-theme-choice="light">Light</button>
          <button type="button" data-theme-choice="dark">Dark</button>
        </div>
      </section>
    </article>
    """
  end
end
