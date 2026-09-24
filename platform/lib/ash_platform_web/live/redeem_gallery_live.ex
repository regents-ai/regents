defmodule AshPlatformWeb.RedeemGalleryLive do
  @moduledoc false
  use Phoenix.Component

  @passes 1..1998
  @media "https://media.regents.sh/images/regents-club-pass"
  @opensea "https://opensea.io/assets/base/0x2208aadbdecd47d3b4430b5b75a175f6d885d487"

  attr :signed_in, :boolean, required: true
  attr :mine, :boolean, required: true
  attr :owned, :map, required: true

  # Every pass is drawn from the same media the collection's metadata names,
  # and each one opens its own OpenSea page. The full grid stays in the page
  # while "My passes" is on, hidden, so switching back sends nothing again.
  def page(assigns) do
    assigns = assign(assigns, all: @passes, status: status(assigns))

    ~H"""
    <section class="gallery-page" aria-labelledby="gallery-heading">
      <header class="gallery-heading rg-panel rg-panel--surface rg-panel__body">
        <p class="gallery-kicker">Regents Club</p>
        <h1 id="gallery-heading" tabindex="-1">All 1,998 passes</h1>
        <p class="gallery-lede">
          Every Regents Club Digital Pass, animated as it appears on OpenSea. Redeem an Animata I or II Pass to receive one.
        </p>
        <nav class="gallery-actions" aria-label="Regents Club">
          <.link navigate="/redeem" class="rg-button">
            <span class="rg-button__label">Redeem an Animata</span>
          </.link>
          <a
            href="https://opensea.io/collection/regents-club"
            target="_blank"
            rel="noopener noreferrer"
            class="rg-button rg-button--secondary"
          >
            <span class="rg-button__label">View collection on OpenSea
            <span aria-hidden="true">↗</span></span>
          </a>
        </nav>
        <div class="gallery-filter">
          <button
            id="gallery-mine"
            type="button"
            class="gallery-toggle"
            aria-pressed={to_string(@mine)}
            aria-describedby="gallery-filter-status"
            phx-click="toggle_my_passes"
            disabled={not @signed_in}
          >
            <span class="gallery-toggle__switch" aria-hidden="true"></span>
            <span>My passes</span>
          </button>
          <p id="gallery-filter-status" class="gallery-status" role="status">
            {@status}
            <.link :if={@mine and @owned.status == :ready and @owned.ids == []} navigate="/redeem">
              Redeem an Animata
            </.link>
          </p>
        </div>
        <form id="gallery-jump" class="gallery-jump" phx-hook=".PassJump" hidden={@mine}>
          <label for="gallery-jump-number">Go to pass</label>
          <input
            id="gallery-jump-number"
            name="pass"
            type="number"
            min="1"
            max="1998"
            inputmode="numeric"
            placeholder="1–1998"
            required
          />
          <button type="submit" class="rg-button rg-button--secondary">
            <span class="rg-button__label">Go</span>
          </button>
        </form>
        <script :type={Phoenix.LiveView.ColocatedHook} name=".PassJump">
          export default {
            mounted() {
              this.el.addEventListener("submit", (event) => {
                event.preventDefault()
                const pass = document.getElementById(`pass-${new FormData(this.el).get("pass")}`)
                if (!pass) return
                document.querySelector(".gallery-pass[data-found]")?.removeAttribute("data-found")
                pass.setAttribute("data-found", "")
                pass.scrollIntoView({block: "center"})
                pass.querySelector("a").focus({preventScroll: true})
              })
            }
          }
        </script>
      </header>

      <ul
        :if={@mine and @owned.status == :ready and @owned.ids != []}
        class="gallery-grid"
        aria-label="Your Regents Club passes"
      >
        <.pass :for={id <- @owned.ids} id={id} dom_id={"my-pass-#{id}"} />
      </ul>

      <ul class="gallery-grid" aria-label="Regents Club passes" hidden={@mine}>
        <.pass :for={id <- @all} id={id} dom_id={"pass-#{id}"} />
      </ul>
    </section>
    """
  end

  attr :id, :integer, required: true
  attr :dom_id, :string, required: true

  defp pass(assigns) do
    assigns = assign(assigns, media: @media, opensea: @opensea)

    ~H"""
    <li id={@dom_id} class="gallery-pass">
      <a href={"#{@opensea}/#{@id}"} target="_blank" rel="noopener noreferrer">
        <img
          src={"#{@media}/#{@id}.gif"}
          alt={"Regents Club ##{@id}"}
          width="768"
          height="1024"
          loading="lazy"
          decoding="async"
        />
        <span>#{@id}</span>
      </a>
    </li>
    """
  end

  defp status(%{signed_in: false}), do: "Sign in to see the passes you own."
  defp status(%{mine: false}), do: nil
  defp status(%{owned: %{status: :loading}}), do: "Finding your passes…"

  defp status(%{owned: %{status: :unavailable}}),
    do: "Your passes could not be loaded. Turn My passes off and on to try again."

  defp status(%{owned: %{status: :ready, ids: []}}),
    do: "None of your wallets holds a Regents Club pass yet."

  defp status(%{owned: %{status: :ready, ids: [_]}}), do: "You hold 1 pass."
  defp status(%{owned: %{status: :ready, ids: ids}}), do: "You hold #{length(ids)} passes."
end
