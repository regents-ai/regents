defmodule AshPlatformWeb.SharedProfileHTML do
  use AshPlatformWeb, :html

  def show(assigns) do
    ~H"""
    <main class="regents-profile-page" style="max-width: 42rem; margin: 2rem auto; padding: 1rem;">
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
    </main>
    """
  end
end
