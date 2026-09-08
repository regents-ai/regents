defmodule AshPlatformWeb.SharedProfileHTML do
  use AshPlatformWeb, :html

  def show(assigns) do
    ~H"""
    <main class="regents-profile-page rg-sheet rg-frame">
      <nav aria-label="Account" class="rg-profile-actions">
        <a href="/app">Regents</a>
        <div id="account-control">
          <Regent.Primitives.button
            :if={@account_control.kind == :sign_in}
            data-account-target="sign-in"
          >Sign in</Regent.Primitives.button>
          <Regent.Primitives.button
            :if={@account_control.kind == :signed_in}
            data-account-target="sign-out"
          >Sign out</Regent.Primitives.button>
          <p id="account-auth-status" role="status" hidden></p>
        </div>
      </nav>
      <Regent.Profile.panel />
      <section
        class="rg-profile rg-panel rg-panel--surface"
        data-owned-claims
        aria-labelledby="owned-claims-title"
      >
        <h2 id="owned-claims-title">Historical names</h2>
        <Regent.Primitives.button data-claims-load>Load names</Regent.Primitives.button>
        <p data-claims-status role="status">Load names linked to your verified wallets.</p>
        <ul data-claims-list></ul>
        <Regent.Primitives.button data-claims-more hidden>More names</Regent.Primitives.button>
      </section>
    </main>
    """
  end
end
