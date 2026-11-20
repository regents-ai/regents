defmodule RegentsWeb.CloakLive do
  @moduledoc """
  The `/cloak` product page, with the words from `RegentsWeb.Cloak`: the app's
  icon, the heading and subtitle, Download (a plain link to the newest signed
  build) and Watch, which plays the intro film in a dialog, then the three modes
  beside a drawn picture of the chat window, and the notes.
  """
  use RegentsWeb, :html

  alias RegentsWeb.Cloak

  def page(assigns) do
    assigns =
      assign(assigns,
        pill: Cloak.pill(),
        window: Cloak.window(),
        modes: Enum.with_index(Cloak.modes(), 1)
      )

    ~H"""
    <section id="cloak-page" class="cloak" aria-labelledby="cloak-heading">
      <header class="cloak-hero">
        <img class="cloak-hero__icon" src={~p"/images/cloak/icon.png"} width="72" height="72" alt="" />
        <p class="cloak-pill">
          {@pill.before}<a href={@pill.href}>{@pill.link}</a>{@pill.after}
        </p>
        <h1 id="cloak-heading" tabindex="-1">
          <%= for {line, index} <- Enum.with_index(Cloak.heading()) do %>
            <br :if={index > 0} />{line}
          <% end %>
        </h1>
        <p class="cloak-hero__subtitle">{Cloak.subtitle()}</p>
        <div class="cloak-hero__actions">
          <a id="cloak-download" class="cloak-button cloak-button--main" href={Cloak.download()}>
            <.apple_logo />
            <span>{Cloak.download_label()}</span>
          </a>
          <button
            id="cloak-watch"
            class="cloak-button"
            type="button"
            aria-haspopup="dialog"
            aria-controls="cloak-intro"
          >
            <svg
              viewBox="0 0 24 24"
              aria-hidden="true"
              focusable="false"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
              stroke-linejoin="round"
            >
              <path d="M7 4.5v15l12-7.5z" />
            </svg>
            <span>{Cloak.watch_label()}</span>
            <span class="cloak-button__time">{Cloak.watch_time()}</span>
          </button>
        </div>
        <p class="cloak-hero__facts">{Cloak.facts()}</p>
      </header>

      <section class="cloak-show" aria-labelledby="cloak-modes-heading">
        <div>
          <h2 id="cloak-modes-heading" class="cloak-show__title">{Cloak.modes_title()}</h2>
          <ol class="cloak-modes">
            <li :for={{{name, credit, sentence}, n} <- @modes}>
              <span class="cloak-badge" aria-hidden="true">{n}</span>
              <div>
                <h3>{name}</h3>
                <p :if={credit} class="cloak-modes__credit">
                  {credit.before}<a href={credit.href} target="_blank" rel="noopener noreferrer">{credit.link}</a>{credit.after}
                </p>
                <p>{sentence}</p>
              </div>
            </li>
          </ol>
        </div>

        <div
          class="cloak-window"
          role="img"
          aria-label="The Cloak chat window with its mode switch: Anon, NEAR Private AI, Local Llama and Agent."
        >
          <div class="cloak-window__bar"><i></i><i></i><i></i><span>{@window.title}</span></div>
          <div class="cloak-window__state"><b>{@window.mode}</b>{@window.mode_note}</div>
          <div class="cloak-window__chat">
            <div class="cloak-bubble cloak-bubble--mine">{@window.asked}</div>
            <div class="cloak-bubble">{@window.answered}</div>
          </div>
          <div class="cloak-window__compose">
            <div class="cloak-window__field">{@window.field}</div>
            <div class="cloak-switch">
              <span
                :for={{label, n} <- Enum.with_index(@window.switch, 1)}
                class={label == @window.mode && "is-on"}
              >
                <span :if={n <= length(@modes)} class="cloak-badge">{n}</span>{label}
              </span>
            </div>
            <p class="cloak-window__hint">{@window.hint}</p>
          </div>
        </div>
      </section>

      <section class="cloak-notes" aria-label="Details">
        <div>
          <h2>Needs</h2>
          <p>{Cloak.needs()}</p>
        </div>
        <div>
          <h2>Caution</h2>
          <p>{Cloak.caution()}</p>
        </div>
        <p class="cloak-notes__last">
          {Cloak.feedback().before}<a
            href={Cloak.feedback().href}
            target="_blank"
            rel="noopener noreferrer"
          >{Cloak.feedback().link}</a>{Cloak.feedback().after}
        </p>
      </section>

      <dialog
        id="cloak-intro"
        class="cloak-intro"
        aria-label="Intro"
        phx-hook=".IntroFilm"
        data-trigger="cloak-watch"
      >
        <form method="dialog" class="cloak-intro__bar">
          <button class="cloak-intro__close" type="submit">Close</button>
        </form>
        <video src={~p"/images/cloak/intro.mp4"} controls playsinline preload="none"></video>
      </dialog>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".IntroFilm">
        // Watch opens the film's dialog and plays it. Escape, Close or a press
        // outside the film closes it; the film then stops and goes back to the
        // start, and the browser returns focus to Watch.
        export default {
          mounted() {
            this.js().ignoreAttributes(this.el, ["open"])
            this.film = this.el.querySelector("video")
            this.trigger = document.getElementById(this.el.dataset.trigger)
            this.open = () => {
              this.el.showModal()
              this.film.play().catch(() => {})
            }
            this.trigger.addEventListener("click", this.open)
            this.el.addEventListener("click", (event) => {
              if (event.target === this.el) this.el.close()
            })
            this.el.addEventListener("close", () => {
              this.film.pause()
              this.film.currentTime = 0
            })
          },
          destroyed() {
            this.trigger.removeEventListener("click", this.open)
          }
        }
      </script>
    </section>
    """
  end

  # The Apple mark, filled in the button's ink. The site's icon set (Lucide) has
  # only the fruit.
  defp apple_logo(assigns) do
    ~H"""
    <svg viewBox="0 0 24 24" aria-hidden="true" focusable="false" fill="currentColor">
      <path d="M12.152 6.896c-.948 0-2.415-1.078-3.96-1.04-2.04.027-3.91 1.183-4.961 3.014-2.117 3.675-.546 9.103 1.519 12.09 1.013 1.454 2.208 3.09 3.792 3.039 1.52-.065 2.09-.987 3.935-.987 1.831 0 2.35.987 3.96.948 1.637-.026 2.676-1.48 3.676-2.948 1.156-1.688 1.636-3.325 1.662-3.415-.039-.013-3.182-1.221-3.22-4.857-.026-3.04 2.48-4.494 2.597-4.559-1.429-2.09-3.623-2.324-4.39-2.376-2-.156-3.675 1.09-4.61 1.09zM15.53 3.83c.843-1.012 1.4-2.427 1.245-3.83-1.207.052-2.662.805-3.532 1.818-.78.896-1.454 2.338-1.273 3.714 1.338.104 2.715-.688 3.559-1.701" />
    </svg>
    """
  end
end
