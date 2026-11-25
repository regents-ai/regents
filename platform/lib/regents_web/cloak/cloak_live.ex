defmodule RegentsWeb.Cloak.CloakLive do
  @moduledoc """
  The `/cloak` product page, with the words from `RegentsWeb.Cloak`: the app's
  icon, the heading and subtitle, Watch, releases/docs/source actions, then the
  four modes beside a drawn picture of the chat window, the Local Agent Box &
  Connected Apps showcase, agent reference notes, and the details/feedback
  section.

  `install/1` is `/cloak/install`: the steps that follow a download, beside two
  pictures from the app, the window the download opens and the menu. It offers
  no file.
  """
  use RegentsWeb, :html

  alias Phoenix.LiveView.JS
  alias RegentsWeb.Cloak

  def page(assigns) do
    assigns =
      assign(assigns,
        pill: Cloak.pill(),
        ecosystem: Cloak.ecosystem(),
        window: Cloak.window(),
        modes: Enum.with_index(Cloak.modes(), 1),
        checksums: Cloak.release_checksums()
      )

    ~H"""
    <section id="cloak-page" class="cloak" aria-labelledby="cloak-heading">
      <header class="cloak-hero">
        <img class="cloak-hero__icon" src={~p"/images/cloak/icon.png"} width="72" height="72" alt="" />
        <p class="cloak-pill">
          {@pill.before}<a href={@pill.href}>{@pill.link}</a>{@pill.after}
        </p>
        <h1 id="cloak-heading" tabindex="-1">
          <span class="cloak-hero__first">{hd(Cloak.heading())}</span>
          <span class="cloak-hero__second">{List.last(Cloak.heading())}</span>
        </h1>
        <p class="cloak-hero__subtitle">{Cloak.subtitle()}</p>
        <div class="cloak-hero__actions">
          <button
            id="cloak-watch"
            class="cloak-button cloak-button--main"
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
          <a
            class="cloak-button"
            href={Cloak.releases_url()}
            target="_blank"
            rel="noopener noreferrer"
          >
            <span>View releases</span>
          </a>
          <a class="cloak-button" href={Cloak.docs_path()}>
            <span>Read docs</span>
          </a>
          <a id="cloak-forum-link" class="cloak-button" href={~p"/patchbay/cloak"}>
            <span>{Cloak.forum_label()}</span>
          </a>
          <a
            class="cloak-button"
            href={Cloak.source_url()}
            target="_blank"
            rel="noopener noreferrer"
          >
            <span>View source</span>
          </a>
        </div>
        <p class="cloak-hero__facts">{Cloak.facts()}</p>
      </header>

      <section class="cloak-ecosystem" aria-labelledby="cloak-ecosystem-heading">
        <p id="cloak-ecosystem-heading" class="cloak-ecosystem__eyebrow">
          {Cloak.ecosystem_heading()}
        </p>
        <ul class="cloak-ecosystem__grid">
          <li :for={group <- @ecosystem} class="cloak-ecosystem__group" data-group={group.id}>
            <div class="cloak-ecosystem__logos">
              <%= for {partner, idx} <- Enum.with_index(group.partners) do %>
                <span :if={idx > 0} class="cloak-ecosystem__plus" aria-hidden="true">+</span>
                <a
                  class="cloak-ecosystem__partner"
                  href={partner.href}
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  <.partner_mark id={partner.id} />
                  <span>{partner.name}</span>
                </a>
              <% end %>
            </div>
            <p class="cloak-ecosystem__note">{group.note}</p>
          </li>
        </ul>
      </section>

      <section id="modes" class="cloak-show" aria-labelledby="cloak-modes-heading">
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
          aria-label="The Cloak chat window showing an Original to Sent local prompt rephrasing in zkAPI Anon Inference mode, with mode switch: Local, NEAR AI Gateway, Token Inference, zkAPI Anon Inference, and Agent."
        >
          <div class="cloak-window__bar"><i></i><i></i><i></i><span>{@window.title}</span></div>
          <div class="cloak-window__state"><b>{@window.mode}</b>{@window.mode_note}</div>
          <div class="cloak-window__chat">
            <div class="cloak-bubble cloak-bubble--mine">
              <span class="cloak-bubble__label">{@window.original_label}</span>
              {@window.original}
            </div>
            <div class="cloak-bubble cloak-bubble--sent">
              <span class="cloak-bubble__label">{@window.sent_label}</span>
              {@window.sent}
            </div>
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

      <section id="agent" class="cloak-agent" aria-labelledby="cloak-agent-heading">
        <div class="cloak-agent__head">
          <h2 id="cloak-agent-heading">{Cloak.agent().title}</h2>
          <p>{Cloak.agent().summary}</p>
        </div>
        <ul class="cloak-agent__list">
          <li :for={bullet <- Cloak.agent().bullets}>{bullet}</li>
        </ul>
        <div class="cloak-agent__actions">
          <a class="cloak-button" href={Cloak.agent().docs_href}>
            <span>{Cloak.agent().docs_label}</span>
          </a>
        </div>
      </section>

      <section class="cloak-agent-docs" aria-labelledby="cloak-agent-docs-heading">
        <div class="cloak-agent-docs__head">
          <h2 id="cloak-agent-docs-heading">{Cloak.agent_docs_title()}</h2>
          <p>{Cloak.agent_docs_intro()}</p>
        </div>
        <div class="cloak-agent-docs__list">
          <details
            :for={doc <- Cloak.agent_docs()}
            id={"cloak-agent-doc-#{doc.id}"}
            class="cloak-agent-doc"
            phx-mounted={JS.ignore_attributes(["open"])}
          >
            <summary>{doc.summary}</summary>
            <p>{doc.body}</p>
          </details>
        </div>
      </section>

      <section id="verify" class="cloak-verify" aria-labelledby="cloak-verify-heading">
        <div class="cloak-verify__head">
          <h2 id="cloak-verify-heading">Verify your download</h2>
          <p>
            Verify every build independently using macOS's built-in Terminal tools and compare the output across
            this page,
            <a href={@checksums.release_url} target="_blank" rel="noopener noreferrer">
              GitHub Releases
            </a>
            (<a href={@checksums.sums_url} target="_blank" rel="noopener noreferrer">SHA256SUMS.txt</a>),
            and Cloak's <strong>Settings → Status</strong>
            pane.
          </p>
        </div>

        <dl class="cloak-verify__facts">
          <div>
            <dt>Published release</dt>
            <dd><code>{@checksums.tag}</code></dd>
          </div>
          <div>
            <dt>Apple Developer ID Team</dt>
            <dd><code>{@checksums.team_id}</code></dd>
          </div>
          <div class="cloak-verify__wide">
            <dt>DMG SHA-256 ({@checksums.dmg_filename})</dt>
            <dd><code>{@checksums.dmg_sha256}</code></dd>
          </div>
          <div :for={{label, value} <- @checksums.extra_hashes} class="cloak-verify__wide">
            <dt>{label}</dt>
            <dd><code>{value}</code></dd>
          </div>
        </dl>

        <div class="cloak-verify__commands">
          <div :for={{label, cmd} <- @checksums.commands} class="cloak-verify__cmd">
            <span class="cloak-verify__cmd-label">{label}</span>
            <pre><code>{cmd}</code></pre>
          </div>
        </div>
      </section>

      <section class="cloak-notes" aria-label="Details">
        <div>
          <h2>Needs</h2>
          <p>{Cloak.needs()}</p>
        </div>
        <div>
          <h2>Caution · Beta</h2>
          <p>
            {Cloak.caution()}
            <a href="/docs/cloak/wallets">Read Wallet Security, Failure Modes &amp; 30-Day zkAPI Limit</a>.
          </p>
        </div>
        <p class="cloak-notes__last">
          {Cloak.feedback().before}<a
            href={Cloak.feedback().href}
            target="_blank"
            rel="noopener noreferrer"
          >{Cloak.feedback().link}</a>{Cloak.feedback().github_middle}<a
            href={Cloak.feedback().github_href}
            target="_blank"
            rel="noopener noreferrer"
          >{Cloak.feedback().github_link}</a>{Cloak.feedback().middle}<a
            href={Cloak.feedback().social_href}
            target="_blank"
            rel="noopener noreferrer"
          >{Cloak.feedback().social_link}</a>{Cloak.feedback().after}
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

  def install(assigns) do
    assigns =
      assign(assigns,
        steps: Enum.with_index(Cloak.install_steps(), 1),
        checksums: Cloak.release_checksums()
      )

    ~H"""
    <section id="cloak-install" class="cloak" aria-labelledby="cloak-install-heading">
      <header class="cloak-hero">
        <img class="cloak-hero__icon" src={~p"/images/cloak/icon.png"} width="72" height="72" alt="" />
        <h1 id="cloak-install-heading" class="cloak-hero__small" tabindex="-1">
          {Cloak.install_heading()}
        </h1>
        <div class="cloak-hero__actions">
          <.link navigate={~p"/cloak"} class="rg-button rg-button--quiet">
            <span class="rg-button__label">Back to Cloak</span>
          </.link>
        </div>
        <p class="cloak-hero__facts">{Cloak.facts()}</p>
      </header>

      <section class="cloak-show cloak-show--steps" aria-label="Steps">
        <ol class="cloak-modes">
          <li :for={{{title, sentence}, n} <- @steps}>
            <span class="cloak-badge" aria-hidden="true">{n}</span>
            <div>
              <h2>{title}</h2>
              <p>{sentence}</p>
            </div>
          </li>
        </ol>
        <div class="cloak-pictures">
          <img
            src={~p"/images/cloak/install-window.png"}
            width="640"
            height="388"
            loading="lazy"
            alt="The window the download opens: Cloak, an arrow, and Applications."
          />
          <img
            class="cloak-pictures__menu"
            src={~p"/images/cloak/menu-bar.png"}
            width="460"
            height="270"
            loading="lazy"
            alt="Cloak's crown in the menu bar with its control panel open: status, Start, mode switcher, Cover Traffic, Chat, Serving, and Settings."
          />
        </div>
      </section>

      <section id="verify" class="cloak-verify" aria-labelledby="cloak-verify-heading">
        <div class="cloak-verify__head">
          <h2 id="cloak-verify-heading">Verify your download</h2>
          <p>
            Verify every build independently using macOS's built-in Terminal tools and compare the output across
            this page,
            <a href={@checksums.release_url} target="_blank" rel="noopener noreferrer">
              GitHub Releases
            </a>
            (<a href={@checksums.sums_url} target="_blank" rel="noopener noreferrer">SHA256SUMS.txt</a>),
            and Cloak's <strong>Settings → Status</strong>
            pane.
          </p>
        </div>

        <dl class="cloak-verify__facts">
          <div>
            <dt>Published release</dt>
            <dd><code>{@checksums.tag}</code></dd>
          </div>
          <div>
            <dt>Apple Developer ID Team</dt>
            <dd><code>{@checksums.team_id}</code></dd>
          </div>
          <div class="cloak-verify__wide">
            <dt>DMG SHA-256 ({@checksums.dmg_filename})</dt>
            <dd><code>{@checksums.dmg_sha256}</code></dd>
          </div>
          <div :for={{label, value} <- @checksums.extra_hashes} class="cloak-verify__wide">
            <dt>{label}</dt>
            <dd><code>{value}</code></dd>
          </div>
        </dl>

        <div class="cloak-verify__commands">
          <div :for={{label, cmd} <- @checksums.commands} class="cloak-verify__cmd">
            <span class="cloak-verify__cmd-label">{label}</span>
            <pre><code>{cmd}</code></pre>
          </div>
        </div>
      </section>

      <section class="cloak-notes" aria-label="Details">
        <div>
          <h2>Updates</h2>
          <p>{Cloak.updates()}</p>
        </div>
        <div>
          <h2>Caution · Beta</h2>
          <p>
            {Cloak.caution()}
            <a href="/docs/cloak/wallets">Read Wallet Security, Failure Modes &amp; 30-Day zkAPI Limit</a>.
          </p>
        </div>
        <p class="cloak-notes__last">
          {Cloak.feedback().before}<a
            href={Cloak.feedback().href}
            target="_blank"
            rel="noopener noreferrer"
          >{Cloak.feedback().link}</a>{Cloak.feedback().github_middle}<a
            href={Cloak.feedback().github_href}
            target="_blank"
            rel="noopener noreferrer"
          >{Cloak.feedback().github_link}</a>{Cloak.feedback().middle}<a
            href={Cloak.feedback().social_href}
            target="_blank"
            rel="noopener noreferrer"
          >{Cloak.feedback().social_link}</a>{Cloak.feedback().after}
        </p>
      </section>
    </section>
    """
  end

  attr :id, :string, required: true

  defp partner_mark(%{id: "boundless"} = assigns) do
    ~H"""
    <svg class="cloak-ecosystem__mark" viewBox="0 0 24 24" aria-hidden="true" focusable="false">
      <path
        fill="none"
        stroke="currentColor"
        stroke-width="2"
        stroke-linecap="round"
        stroke-linejoin="round"
        d="M7.5 16.5a4.5 4.5 0 1 1 3.2-7.7l2.6 2.6a4.5 4.5 0 1 0 3.2-7.7M16.5 7.5a4.5 4.5 0 1 1-3.2 7.7l-2.6-2.6a4.5 4.5 0 1 0-3.2 7.7"
      />
      <circle cx="7.5" cy="12" r="1.5" fill="currentColor" />
      <circle cx="16.5" cy="12" r="1.5" fill="currentColor" />
    </svg>
    """
  end

  defp partner_mark(%{id: "tempo"} = assigns) do
    ~H"""
    <svg class="cloak-ecosystem__mark" viewBox="0 0 24 24" aria-hidden="true" focusable="false">
      <path
        fill="currentColor"
        d="M4 5.5h16a1 1 0 0 1 0 2H4a1 1 0 0 1 0-2Zm5 5.5h10a1 1 0 0 1 0 2H9a1 1 0 0 1 0-2Z"
      />
      <path
        fill="currentColor"
        opacity="0.72"
        d="M11 7.5h2.2L10.8 19H8.6L11 7.5Zm4.4 9h4.6a1 1 0 0 1 0 2h-4.6a1 1 0 0 1 0-2Z"
      />
    </svg>
    """
  end

  defp partner_mark(%{id: "venice"} = assigns) do
    ~H"""
    <svg class="cloak-ecosystem__mark" viewBox="0 0 24 24" aria-hidden="true" focusable="false">
      <path fill="currentColor" d="M3.5 5h3.6L12 16.4 16.9 5h3.6L13.5 20h-3L3.5 5Z" />
      <path fill="currentColor" opacity="0.55" d="M9.4 5h5.2L12 10.8 9.4 5Z" />
    </svg>
    """
  end

  defp partner_mark(%{id: "base"} = assigns) do
    ~H"""
    <svg class="cloak-ecosystem__mark" viewBox="0 0 24 24" aria-hidden="true" focusable="false">
      <path
        fill="currentColor"
        fill-rule="evenodd"
        clip-rule="evenodd"
        d="M12 3a9 9 0 1 0 8.95 10H11.5v-2h9.45A9 9 0 0 0 12 3Z"
      />
    </svg>
    """
  end

  defp partner_mark(%{id: "eigenlayer"} = assigns) do
    ~H"""
    <svg class="cloak-ecosystem__mark" viewBox="0 0 24 24" aria-hidden="true" focusable="false">
      <path fill="currentColor" d="M5 4h3.2v16H5V4Zm5.4 0h3.2v9.5h-3.2V4Zm5.4 0H19v6.2h-3.2V4Z" />
      <path fill="currentColor" opacity="0.6" d="M10.4 15.5h8.6V20h-8.6v-4.5Z" />
    </svg>
    """
  end

  defp partner_mark(%{id: "ethereum"} = assigns) do
    ~H"""
    <svg class="cloak-ecosystem__mark" viewBox="0 0 24 24" aria-hidden="true" focusable="false">
      <path fill="currentColor" d="M12 2.2 5.8 12.3 12 16l6.2-3.7L12 2.2Z" />
      <path fill="currentColor" opacity="0.65" d="M12 17.5 5.8 13.8 12 21.8l6.2-8L12 17.5Z" />
    </svg>
    """
  end

  defp partner_mark(assigns) do
    ~H"""
    <svg class="cloak-ecosystem__mark" viewBox="0 0 24 24" aria-hidden="true" focusable="false">
      <circle cx="12" cy="12" r="7" fill="currentColor" opacity="0.7" />
    </svg>
    """
  end
end
