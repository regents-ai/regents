defmodule AshPlatformWeb.FormationLive do
  @moduledoc false

  use Phoenix.LiveComponent

  def page(assigns) do
    ~H"""
    <section id="formation" class="formation-page">
      <header class="formation-heading rg-panel rg-panel--surface rg-panel__body">
        <p class="formation-kicker">Formation</p>
        <h1>Regent runs best on Hermes</h1>
        <p>
          Create and manage your Regent as a Hermes agent in Nous Portal.
        </p>
      </header>

      <section
        class="formation-handoff rg-panel rg-panel--surface rg-panel__body rg-support-panel"
        aria-label="Nous Portal"
      >
        <a
          id="formation-nous-portal-link"
          class="rg-button formation-link"
          href="https://portal.nousresearch.com/cloud"
          target="_blank"
          rel="noopener noreferrer"
          aria-describedby="formation-nous-portal-disclosure"
        ><span class="rg-button__label">
          Open Nous Portal
        </span></a>
        <p id="formation-nous-portal-disclosure">
          Nous Portal opens in a new tab. Your Hermes agent can complete Autolaunch in their cloud runtime.
        </p>
      </section>
    </section>
    """
  end
end
