defmodule RegentsWeb.CreditsLive do
  @moduledoc """
  The two Regent Credits pages regents.sh hosts for every Regent site: the
  refund rules every Buy Credits panel links to, and the admin page where a
  Credits admin gives Credits and handles refunds. The library refuses every
  admin action to anyone its `:admins` setting does not name; this page only
  decides what to show.
  """
  use Phoenix.Component

  alias Regents.Credits

  def refunds(assigns) do
    ~H"""
    <article id="credits-refunds-page" class="account-page credits-page">
      <section class="account-panel">
        <RegentsWeb.CreditsRefundRules.rules />
      </section>
    </article>
    """
  end

  attr :account, :map, default: nil

  def admin(assigns) do
    assigns = assign(assigns, :admin?, Credits.admin?(assigns.account))

    ~H"""
    <article id="credits-admin-page" class="account-page credits-page">
      <header class="account-heading">
        <p class="account-kicker">Regents Labs</p>
        <h1 tabindex="-1">Credits admin</h1>
        <p class="account-lede">Give Credits, find purchases and send refunds.</p>
      </header>

      <section :if={is_nil(@account)} class="account-panel">
        <h2>Sign in to see this page</h2>
        <Regent.Primitives.button type="button" data-account-target="sign-in">
          Sign in
        </Regent.Primitives.button>
      </section>

      <section :if={@account && !@admin?} class="account-panel">
        <h2>This page is for Credits admins</h2>
        <p>
          Your Credits and what your agents may spend are on your
          <.link patch="/account">Account</.link>
          page.
        </p>
      </section>

      <section :if={@admin?} class="account-panel">
        <.live_component
          module={RegentsWeb.CreditsAdmin}
          id="credits-admin"
          actor={Credits.admin(@account)}
        />
      </section>
    </article>
    """
  end
end
