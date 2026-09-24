defmodule AshPlatformWeb.RedeemGalleryLive do
  @moduledoc false
  use Phoenix.Component

  @passes 1..1998
  @media "https://media.regents.sh/images/regents-club-pass"
  @opensea "https://opensea.io/assets/base/0x2208aadbdecd47d3b4430b5b75a175f6d885d487"

  # Every pass is drawn from the same media the collection's metadata names,
  # and each one opens its own OpenSea page. Nothing here reads a chain.
  def page(assigns) do
    assigns = assign(assigns, passes: @passes, media: @media, opensea: @opensea)

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
        <form id="gallery-jump" class="gallery-jump" phx-hook=".PassJump">
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

      <ul class="gallery-grid" aria-label="Regents Club passes">
        <li :for={id <- @passes} id={"pass-#{id}"} class="gallery-pass">
          <a href={"#{@opensea}/#{id}"} target="_blank" rel="noopener noreferrer">
            <img
              src={"#{@media}/#{id}.gif"}
              alt={"Regents Club ##{id}"}
              width="768"
              height="1024"
              loading="lazy"
              decoding="async"
            />
            <span>#{id}</span>
          </a>
        </li>
      </ul>
    </section>
    """
  end
end
