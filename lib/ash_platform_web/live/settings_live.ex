defmodule AshPlatformWeb.SettingsLive do
  @moduledoc false

  use AshPlatformWeb, :html

  attr(:rest, :global)

  def page(assigns) do
    ~H"""
    <article class="settings-page" {@rest}>
      <header class="settings-page__header">
        <h1>Settings</h1>
      </header>

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
