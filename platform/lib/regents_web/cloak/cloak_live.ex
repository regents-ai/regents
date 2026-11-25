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
        ecosystem: Cloak.ecosystem(),
        window: Cloak.window(),
        modes: Enum.with_index(Cloak.modes(), 1),
        checksums: Cloak.release_checksums()
      )

    ~H"""
    <section id="cloak-page" class="cloak" aria-labelledby="cloak-heading">
      <header class="cloak-hero">
        <picture class="cloak-hero__icon-wrap">
          <source srcset={~p"/images/cloak/icon.png"} media="(prefers-reduced-motion: reduce)" />
          <img
            class="cloak-hero__icon"
            src={~p"/images/cloak/icon-loop.gif"}
            width="128"
            height="128"
            alt=""
          />
        </picture>
        <p class="cloak-pill">{Cloak.pill()}</p>
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
        <h2 id="cloak-ecosystem-heading" class="cloak-ecosystem__eyebrow">
          {Cloak.ecosystem_heading()}
        </h2>
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
                  <span class={if Map.get(partner, :wordmark), do: "cloak-sr-only"}>{partner.name}</span>
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
                  <%= for part <- credit do %>
                    <%= case part do %>
                      <% {:text, text} -> %>
                        {text}
                      <% {:link, label, href} -> %>
                        <a href={href} target="_blank" rel="noopener noreferrer">{label}</a>
                    <% end %>
                  <% end %>
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
                <span :if={n <= 4} class="cloak-badge">{n}</span>{label}
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
            Compare checksums across this page,
            <a href={@checksums.release_url} target="_blank" rel="noopener noreferrer">
              GitHub Releases
            </a>
            (<a href={@checksums.sums_url} target="_blank" rel="noopener noreferrer">SHA256SUMS.txt</a>),
            and <strong>Settings → Status</strong>.
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
            <a href="/docs/cloak/wallets">Wallet security &amp; 30-day zkAPI limit</a>.
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
        <picture class="cloak-hero__icon-wrap">
          <source srcset={~p"/images/cloak/icon.png"} media="(prefers-reduced-motion: reduce)" />
          <img
            class="cloak-hero__icon"
            src={~p"/images/cloak/icon-loop.gif"}
            width="128"
            height="128"
            alt=""
          />
        </picture>
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
            Compare checksums across this page,
            <a href={@checksums.release_url} target="_blank" rel="noopener noreferrer">
              GitHub Releases
            </a>
            (<a href={@checksums.sums_url} target="_blank" rel="noopener noreferrer">SHA256SUMS.txt</a>),
            and <strong>Settings → Status</strong>.
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
            <a href="/docs/cloak/wallets">Wallet security &amp; 30-day zkAPI limit</a>.
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

  defp partner_mark(%{id: "thinking-machines"} = assigns) do
    ~H"""
    <svg
      class="cloak-ecosystem__wordmark"
      viewBox="0 0 332 126"
      aria-hidden="true"
      focusable="false"
    >
      <g fill="currentColor" fill-rule="evenodd">
        <path d="M14 2H48V9H34.5V47H27.5V9H14Z" />
        <path d="M57 2H64V21H85V2H92V47H85V28H64V47H57Z" />
        <path d="M104 2H111V47H104Z" />
        <path d="M124 2H131L151 34V2H158V47H151L131 15V47H124Z" />
        <path d="M171 2H178V21H185L197 2H205.5L191.5 24.5L206 47H197.5L185 28H178V47H171Z" />
        <path d="M215 2H222V47H215Z" />
        <path d="M234 2H241L262 34V2H269V47H262L241 15V47H234Z" />
        <path d="M288 2H309L316 9V15H309V11.5L306.5 9H290.5L288 11.5V37.5L290.5 40H306.5L309 37.5V29H299V22.5H316V40L309 47H288L281 40V9Z" />
        <path d="M2 79H10L23 108L36 79H44V124H36.5V95.5L26 118H20L9.5 95.5V124H2Z" />
        <path d="M67.5 79H75.5L91 124H83.5L80 113.5H63L59.5 124H52ZM65.2 106.8H77.8L71.5 87.5Z" />
        <path d="M104.5 79H126L133 86V92H125.5V88.5L123 86H107.5L105 88.5V114.5L107.5 117H123L125.5 114.5V111H133V117L126 124H104.5L97.5 117V86Z" />
        <path d="M143 79H150V98H171V79H178V124H171V105H150V124H143Z" />
        <path d="M190 79H197V124H190Z" />
        <path d="M210 79H217L237 111V79H244V124H237L217 92V124H210Z" />
        <path d="M257 79H288V86H264V98H286V104.5H264V117H288V124H257Z" />
        <path d="M303.5 79H323.5L330 85.5V91H322.5V88L320.5 86H306.5L304.5 88V95.5L306.5 97.5H323.5L330 104V117.5L323.5 124H303.5L297 117.5V111H304.5V115L306.5 117H320.5L322.5 115V106.5L320.5 104.5H303.5L297 98V85.5Z" />
      </g>
    </svg>
    """
  end

  defp partner_mark(%{id: "boundless"} = assigns) do
    ~H"""
    <svg class="cloak-ecosystem__mark" viewBox="0 0 535 511" aria-hidden="true" focusable="false">
      <path
        fill="currentColor"
        fill-rule="evenodd"
        d="M55.9661 122.74C105.006 91.6142 170.953 105.998 219.334 130.138C245.394 143.142 269.246 159.267 291.515 177.932C254.427 160.141 215.636 144.803 173.846 146.054C152.492 147.086 134.815 156.423 131.243 178.414C129.586 188.612 131.07 198.526 133.652 208.282C140.707 234.956 159.304 269.077 175.459 291.316L186.927 307.108C208.129 336.302 233.016 362.212 260.481 385.829C293.293 414.041 331.744 437.021 374.804 446.523C428.665 458.407 484.762 442.444 516.595 394.814C523.489 384.501 528.346 374.118 533.192 362.275C534.943 375.024 535.795 387.671 534.018 400.843C529.874 431.632 511.107 460.181 485.815 479.047C467.469 492.728 446.617 501.581 424.312 506.442C346.86 523.323 261.301 490.716 196.722 451.3C175.107 438.109 154.988 423.757 135.851 407.281C105.186 380.874 77.7052 351.53 54.9108 318.148C33.7289 287.127 14.843 248.948 12.5502 210.862C10.426 175.606 25.1856 142.278 55.9661 122.74ZM102.604 151.823C66.4523 164.559 52.2959 192.689 60.216 229.083C67.3155 261.698 86.5295 293.72 106.757 320.122C151.71 378.791 215.458 428.135 284.88 456.558C286.465 457.208 288.623 455.916 289.016 455.055C289.409 454.194 289.211 451.794 288.329 451.247C228.942 414.448 177.897 369.798 138.358 312.184C117.684 282.06 99.9723 248.94 93.113 212.727C89.2096 192.123 90.3014 170.221 102.604 151.823Z"
      />
      <path
        fill="currentColor"
        fill-rule="evenodd"
        d="M73.1511 16.0515C114.648 -2.06201 160.812 -3.64356 204.194 5.3295C231.545 10.9876 257.1 19.3091 282.475 30.4655C314.871 44.7061 345.575 61.4151 373.885 82.417C392.863 96.5004 410.136 111.821 427.097 128.192C464.073 163.883 500.496 211.167 516.584 260.357C526.079 289.391 527.662 323.354 514.147 351.846C501.795 377.891 478.647 396.804 451.077 404.945C395.01 421.499 331.701 395.204 286.124 364.038C270.887 353.34 256.662 342.401 242.636 329.66C274.85 345.364 306.456 360.365 342.15 363.394C359.136 364.837 377.757 362.436 388.948 348.833C402.486 332.376 400.624 309.642 395.397 290.033C386.304 255.896 366.091 221.188 344.698 193.259C327.353 170.611 308.129 150.212 286.338 131.699C259.831 109.184 230.28 91.0555 197.505 78.583C160.824 64.6278 118.458 58.2813 80.0496 70.6508C51.6501 79.7965 27.8247 98.7641 13.1506 124.701C9.31342 131.482 6.69038 137.613 3.24451 145.255L1.41311 134.944C-5.2781 97.2572 12.3117 58.2347 43.1983 34.1713C52.6468 26.8105 62.1696 20.8451 73.1511 16.0515ZM249.504 55.1847C247.982 54.5921 245.876 55.4397 245.215 56.4913C244.609 57.4604 245.134 59.8681 246.356 60.5912C264.262 71.1805 281.328 81.9404 298.336 93.9205L329.401 118.067C360.89 144.562 387.858 175.356 408.807 210.836C427.051 241.74 440.919 279.207 438.698 315.847C437.568 334.468 431.257 351.421 419.65 366.716C433.389 364.548 445.409 359.583 456.073 351.232L458.06 349.552C467.752 341.009 473.694 330.462 476.769 318.16C482.157 293.134 474.082 266.201 463.234 243.738C456.004 228.767 448.165 214.671 437.87 201.702L414.023 171.656C389.834 144.47 363.032 120.063 333.068 99.0095C307.154 80.8032 279.039 66.6706 249.504 55.1847Z"
      />
    </svg>
    """
  end

  defp partner_mark(%{id: "tempo"} = assigns) do
    ~H"""
    <svg class="cloak-ecosystem__mark" viewBox="0 0 730 750" aria-hidden="true" focusable="false">
      <path fill="currentColor" d="M258 750L447 170L677 170L730 0L53 0L0 170L243 170L53 750Z" />
    </svg>
    """
  end

  defp partner_mark(%{id: "venice"} = assigns) do
    ~H"""
    <svg class="cloak-ecosystem__mark" viewBox="0 0 79 89" aria-hidden="true" focusable="false">
      <path
        fill="currentColor"
        fill-rule="evenodd"
        d="M25.5614 59.6096C24.1058 58.5274 22.3489 57.6207 20.4061 57.0699C18.4633 56.5191 16.3346 56.3243 14.2531 56.5552C12.1716 56.7861 10.1374 57.4427 8.36251 58.4059C6.58769 59.369 5.07223 60.6388 3.88911 62.0137C2.70275 63.3858 1.66918 65.0712 0.976934 66.9682C0.284683 68.8652 -0.066254 70.9738 0.0108757 73.0666C0.0879638 75.1594 0.59312 77.2365 1.42305 79.0774C2.25301 80.9183 3.40779 82.5231 4.69195 83.8042C5.97303 85.0883 7.57779 86.2431 9.4187 87.0731C11.2596 87.903 13.3367 88.4081 15.4295 88.4852C17.5223 88.5624 19.6309 88.2114 21.5279 87.5192C23.4249 86.8269 25.1103 85.7934 26.4824 84.607C27.8573 83.4239 29.1271 81.9084 30.0903 80.1336C31.0534 78.3587 31.71 76.3245 31.9409 74.243C32.1718 72.1615 31.977 70.0328 31.4262 68.09C30.8755 66.1472 29.9687 64.3904 28.8865 62.9347L32.4611 59.3601L35.063 61.962H36.5408L38.3244 60.1784V58.7006L35.7225 56.0987L39.5 52.3212L43.2775 56.0987L40.6756 58.7006V60.1784L42.4592 61.962H43.937L46.5389 59.3601L50.1135 62.9347C49.0313 64.3904 48.1245 66.1472 47.5738 68.09C47.023 70.0328 46.8282 72.1615 47.0591 74.243C47.29 76.3245 47.9466 78.3587 48.9097 80.1336C49.8729 81.9084 51.1427 83.4239 52.5176 84.607C53.8897 85.7934 55.5751 86.8269 57.4721 87.5192C59.3691 88.2114 61.4777 88.5624 63.5705 88.4852C65.6633 88.4081 67.7403 87.903 69.5813 87.0731C71.4222 86.2431 73.027 85.0883 74.308 83.8042C75.5922 82.5231 76.747 80.9183 77.5769 79.0774C78.4069 77.2365 78.912 75.1594 78.9891 73.0666C79.0663 70.9738 78.7153 68.8652 78.0231 66.9682C77.3308 65.0712 76.2972 63.3858 75.1109 62.0137C73.9278 60.6388 72.4123 59.369 70.6374 58.4059C68.8626 57.4427 66.8284 56.7861 64.7469 56.5552C62.6654 56.3243 60.5367 56.5191 58.5939 57.0699C56.6511 57.6207 54.8942 58.5274 53.4386 59.6096L49.9305 56.0959L52.531 53.4954V52.0176L50.6837 50.1703H49.2059L46.604 52.7722L42.8251 48.9961L62.6362 29.185L70.6558 37.2045V28.8603H79L70.9804 20.8408L79 12.8212V11.3434L77.1527 9.49612H75.6749L39.5 45.671L3.32508 9.49612H1.84728L0 11.3434V12.8212L8.01957 20.8408L0 28.8603H8.34422V37.2045L16.3637 29.185L36.1749 48.9961L32.396 52.7722L29.7941 50.1703H28.3163L26.469 52.0176V53.4954L29.0695 56.0959L25.5614 59.6096ZM57.7097 77.9616C56.894 79.6349 57.0634 81.9536 58.1137 83.4906C59.0787 85.0824 61.1198 86.1956 62.9806 86.1449C64.8415 86.1956 66.8826 85.0824 67.8476 83.4906C68.8979 81.9536 69.0674 79.6349 68.2516 77.9616L68.4548 77.7428C70.1279 78.5629 72.4501 78.3968 73.9895 77.3469C75.584 76.3828 76.6997 74.3394 76.6488 72.4767C76.6997 70.6141 75.584 68.5708 73.9895 67.6066C72.4501 66.5567 70.1279 66.3906 68.4548 67.2107L68.2516 66.992C69.0674 65.3187 68.8979 62.9999 67.8476 61.463C66.8826 59.8711 64.8415 58.7579 62.9806 58.8087C61.1198 58.7579 59.0787 59.8711 58.1137 61.463C57.0634 62.9999 56.894 65.3187 57.7097 66.992L57.5066 67.2107C55.8334 66.3906 53.5112 66.5567 51.9718 67.6066C50.3773 68.5708 49.2616 70.6141 49.3126 72.4767C49.2616 74.3394 50.3773 76.3828 51.9718 77.3469C53.5112 78.3968 55.8334 78.5629 57.5066 77.7428L57.7097 77.9616ZM20.8855 83.4906C21.9358 81.9536 22.1052 79.6349 21.2895 77.9616L21.4927 77.7428C23.1658 78.5629 25.488 78.3968 27.0274 77.3469C28.6219 76.3828 29.7376 74.3394 29.6867 72.4767C29.7376 70.6141 28.6219 68.5708 27.0274 67.6066C25.488 66.5567 23.1658 66.3906 21.4927 67.2107L21.2895 66.992C22.1052 65.3187 21.9358 62.9999 20.8855 61.463C19.9205 59.8711 17.8794 58.7579 16.0185 58.8087C14.1577 58.7579 12.1166 59.8711 11.1516 61.463C10.1013 62.9999 9.93188 65.3187 10.7476 66.992L10.5445 67.2107C8.87131 66.3906 6.54913 66.5567 5.00974 67.6066C3.41523 68.5708 2.29949 70.6141 2.35045 72.4767C2.29949 74.3394 3.41523 76.3828 5.00974 77.3469C6.54913 78.3968 8.87131 78.5629 10.5445 77.7428L10.7476 77.9616C9.93188 79.6349 10.1013 81.9536 11.1516 83.4906C12.1166 85.0824 14.1577 86.1956 16.0185 86.1449C17.8794 86.1956 19.9205 85.0824 20.8855 83.4906Z"
      />
      <path
        fill="currentColor"
        fill-rule="evenodd"
        d="M39.4736 9.49609L48.9698 0L53.6721 4.70237V20.5533L40.6492 33.5761H38.2981L25.2751 20.5533V4.70237L29.9775 0L39.4736 9.49609ZM29.9776 3.32509L38.2981 11.6456V26.926L29.9776 18.6055V3.32509ZM40.6496 11.6456L48.9702 3.32509V18.6055L40.6496 26.926V11.6456Z"
      />
    </svg>
    """
  end

  defp partner_mark(%{id: "base"} = assigns) do
    ~H"""
    <svg class="cloak-ecosystem__mark" viewBox="0 0 111 111" aria-hidden="true" focusable="false">
      <path
        fill="currentColor"
        d="M54.921 110.034C85.359 110.034 110.034 85.402 110.034 55.017C110.034 24.6319 85.359 0 54.921 0C26.0432 0 2.35281 22.1714 0 50.3923H72.8467V59.6416H0C2.35281 87.8625 26.0432 110.034 54.921 110.034Z"
      />
    </svg>
    """
  end

  defp partner_mark(%{id: "eigenlayer"} = assigns) do
    ~H"""
    <svg class="cloak-ecosystem__mark" viewBox="0 0 166 191" aria-hidden="true" focusable="false">
      <path
        fill="currentColor"
        d="M94.8571 95.5122H71.1433V143.254H47.4237V0H0V191H142.286V143.254H94.8571V95.5122Z"
      />
      <path fill="currentColor" d="M166 0H142.291V47.7512H166V0Z" />
      <path
        fill="currentColor"
        d="M118.573 0L72.106 0.00501858V23.8781H94.8584L94.8571 95.5122L142.287 95.4878L142.291 47.7512L118.573 47.7362V0Z"
      />
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
