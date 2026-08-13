defmodule AshPlatformWeb.RegentProfileLive do
  @moduledoc false
  use Phoenix.Component

  alias AshPlatform.PublicIdentity

  attr :regent, :map, default: nil
  attr :status, :atom, required: true

  def page(assigns) do
    ~H"""
    <section id="public-regent-profile" class="regent-profile-page">
      <div :if={@status == :loading} class="regent-profile-status" aria-busy="true">
        Loading Regent profile…
      </div>

      <div :if={@status == :error} class="regent-profile-status" role="alert">
        This Regent profile is unavailable right now.
      </div>

      <div :if={@status == :empty} class="regent-profile-status">
        <p class="regent-profile-kicker">Regents Labs</p>
        <h1>Regent not found</h1>
        <p>This public Regent profile does not exist.</p>
        <.link patch="/app">Return to Regents Labs</.link>
      </div>

      <article :if={@status == :ready && @regent} class="regent-profile-record">
        <p class="regent-profile-kicker">Public Regent</p>
        <img
          :if={@regent.avatar_url}
          src={@regent.avatar_url}
          alt={"#{@regent.display_name} avatar"}
          width="160"
          height="160"
          loading="eager"
          decoding="async"
          referrerpolicy="no-referrer"
        />
        <h1>{@regent.display_name}</h1>
        <p class="regent-profile-slug">regents.sh/regents/{@regent.slug}</p>
        <p>{@regent.summary || "This Regent has not added a public summary yet."}</p>

        <dl>
          <div>
            <dt>Verified wallet</dt>
            <dd>
              <code title={@regent.verified_wallet_address}>
                {PublicIdentity.label(%{wallet_address: @regent.verified_wallet_address})}
              </code>
            </dd>
          </div>
          <div>
            <dt>Formation</dt>
            <dd>Regent formed</dd>
          </div>
          <div>
            <dt>Hermes</dt>
            <dd>Hermes not connected</dd>
          </div>
        </dl>
      </article>
    </section>
    """
  end
end
