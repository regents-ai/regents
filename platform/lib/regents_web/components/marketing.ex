defmodule RegentsWeb.Components.Marketing do
  @moduledoc """
  Shared chrome for the five marketing pages (`/`, `/techtree`, `/keyfleet`,
  `/autolaunch`, `/patchbay`): SVG mark/icon sprite, the Stripe-style fixed top
  bar with its dropdown menus, the phone navigation sheet, the product sub-bar,
  the 5-column huge-name footer, and the 22-tool WebMCP modal dialog.
  """

  use RegentsWeb, :html

  alias RegentsWeb.Components.{AgentTools, ThemeSwitch}
  alias RegentsWeb.Stake.TokenLinks

  @doc "Hidden SVG symbol sprite shared by marketing bar, cards, buttons, and footer."
  def symbols(assigns) do
    ~H"""
    <svg class="symbols" aria-hidden="true">
      <symbol id="mark-crown" viewBox="31 46 178 106">
        <rect x="31" y="46" width="34" height="34" />
        <rect x="103" y="46" width="34" height="34" />
        <rect x="175" y="46" width="34" height="34" />
        <rect x="31" y="82" width="34" height="34" />
        <rect x="67" y="82" width="34" height="34" />
        <rect x="103" y="82" width="34" height="34" />
        <rect x="139" y="82" width="34" height="34" />
        <rect x="175" y="82" width="34" height="34" />
        <rect x="31" y="118" width="34" height="34" />
        <rect x="67" y="118" width="34" height="34" />
        <rect x="103" y="118" width="34" height="34" />
        <rect x="139" y="118" width="34" height="34" />
        <rect x="175" y="118" width="34" height="34" />
      </symbol>
      <symbol id="mark-autolaunch" viewBox="15 33 286 178">
        <rect x="15" y="177" width="34" height="34" />
        <rect x="51" y="177" width="34" height="34" />
        <rect x="87" y="177" width="34" height="34" />
        <rect x="123" y="177" width="34" height="34" />
        <rect x="159" y="177" width="34" height="34" />
        <rect x="195" y="177" width="34" height="34" />
        <rect x="15" y="141" width="34" height="34" />
        <rect x="15" y="105" width="34" height="34" />
        <rect x="87" y="105" width="34" height="34" />
        <rect x="123" y="105" width="34" height="34" />
        <rect x="15" y="69" width="34" height="34" />
        <rect x="159" y="69" width="34" height="34" />
        <rect x="195" y="69" width="34" height="34" />
        <rect x="15" y="33" width="34" height="34" />
        <rect x="231" y="33" width="34" height="34" />
        <rect x="267" y="33" width="34" height="34" />
      </symbol>
      <symbol id="mark-techtree" viewBox="14 47 382 334">
        <rect x="110" y="47" width="22" height="22" />
        <rect x="134" y="47" width="22" height="22" />
        <rect x="158" y="47" width="22" height="22" />
        <rect x="14" y="71" width="22" height="22" />
        <rect x="38" y="71" width="22" height="22" />
        <rect x="62" y="71" width="22" height="22" />
        <rect x="86" y="71" width="22" height="22" />
        <rect x="110" y="71" width="22" height="22" />
        <rect x="134" y="71" width="22" height="22" />
        <rect x="158" y="71" width="22" height="22" />
        <rect x="182" y="71" width="22" height="22" />
        <rect x="206" y="71" width="22" height="22" />
        <rect x="230" y="71" width="22" height="22" />
        <rect x="254" y="71" width="22" height="22" />
        <rect x="110" y="95" width="22" height="22" />
        <rect x="134" y="95" width="22" height="22" />
        <rect x="158" y="95" width="22" height="22" />
        <rect x="134" y="119" width="22" height="22" />
        <rect x="134" y="143" width="22" height="22" />
        <rect x="134" y="167" width="22" height="22" />
        <rect x="134" y="191" width="22" height="22" />
        <rect x="134" y="215" width="22" height="22" />
        <rect x="230" y="215" width="22" height="22" />
        <rect x="254" y="215" width="22" height="22" />
        <rect x="278" y="215" width="22" height="22" />
        <rect x="134" y="239" width="22" height="22" />
        <rect x="158" y="239" width="22" height="22" />
        <rect x="182" y="239" width="22" height="22" />
        <rect x="206" y="239" width="22" height="22" />
        <rect x="230" y="239" width="22" height="22" />
        <rect x="254" y="239" width="22" height="22" />
        <rect x="278" y="239" width="22" height="22" />
        <rect x="302" y="239" width="22" height="22" />
        <rect x="326" y="239" width="22" height="22" />
        <rect x="350" y="239" width="22" height="22" />
        <rect x="374" y="239" width="22" height="22" />
        <rect x="230" y="263" width="22" height="22" />
        <rect x="254" y="263" width="22" height="22" />
        <rect x="278" y="263" width="22" height="22" />
        <rect x="254" y="287" width="22" height="22" />
        <rect x="254" y="311" width="22" height="22" />
        <rect x="254" y="335" width="22" height="22" />
        <rect x="254" y="359" width="22" height="22" />
      </symbol>
      <symbol
        id="icon-chevron"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        stroke-width="1.8"
        stroke-linecap="round"
        stroke-linejoin="round"
      >
        <path d="m6 9 6 6 6-6" />
      </symbol>
      <symbol
        id="icon-copy"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        stroke-width="1.8"
        stroke-linecap="round"
        stroke-linejoin="round"
      >
        <rect width="14" height="14" x="8" y="8" />
        <path d="M4 16V4h12" />
      </symbol>
      <symbol
        id="icon-arrow"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        stroke-width="1.8"
        stroke-linecap="round"
        stroke-linejoin="round"
      >
        <path d="M7 7h10v10" />
        <path d="M7 17 17 7" />
      </symbol>
      <symbol
        id="icon-next"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        stroke-width="1.8"
        stroke-linecap="round"
        stroke-linejoin="round"
      >
        <path d="m9 18 6-6-6-6" />
      </symbol>
      <symbol
        id="icon-x"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        stroke-width="1.8"
        stroke-linecap="round"
        stroke-linejoin="round"
      >
        <path d="M18 6 6 18" />
        <path d="m6 6 12 12" />
      </symbol>
      <symbol
        id="icon-github"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        stroke-width="1.8"
        stroke-linecap="round"
        stroke-linejoin="round"
      >
        <path d="M15 22v-4a4.8 4.8 0 0 0-1-3.5c3 0 6-2 6-5.5.08-1.25-.27-2.48-1-3.5.28-1.15.28-2.35 0-3.5 0 0-1 0-3 1.5-2.64-.5-5.36-.5-8 0C6 2 5 2 5 2c-.3 1.15-.3 2.35 0 3.5A5.403 5.403 0 0 0 4 9c0 3.5 3 5.5 6 5.5-.39.49-.68 1.05-.85 1.65-.17.6-.22 1.23-.15 1.85v4" />
        <path d="M9 18c-4.51 2-5-2-7-2" />
      </symbol>
      <symbol id="icon-xlogo" viewBox="0 0 24 24" fill="currentColor">
        <path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z" />
      </symbol>
      <symbol
        id="icon-plus"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        stroke-width="1.8"
        stroke-linecap="round"
        stroke-linejoin="round"
      >
        <path d="M5 12h14" />
        <path d="M12 5v14" />
      </symbol>
      <symbol
        id="icon-check"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        stroke-width="1.8"
        stroke-linecap="round"
        stroke-linejoin="round"
      >
        <path d="M20 6 9 17l-5-5" />
      </symbol>
    </svg>
    """
  end

  attr :current, :string, default: "regents"
  slot :actions

  @doc "The marketing navigation on a page with its own content layout."
  def navigation(assigns) do
    ~H"""
    <div data-public-header>
      <.symbols />
      <.bar current={@current}>
        <:actions>{render_slot(@actions)}</:actions>
      </.bar>
      <.sheet />
    </div>
    """
  end

  attr :current, :string, default: "regents"
  attr :over_hero, :boolean, default: false
  attr :cta_label, :string, default: "Enter App"
  attr :cta_href, :string, default: "/app"
  attr :cta_external, :boolean, default: false
  attr :cta_brand, :boolean, default: false
  slot :actions

  def bar(assigns) do
    assigns =
      assign(assigns,
        buy_url: TokenLinks.buy(),
        chart_url: TokenLinks.chart()
      )

    ~H"""
    <header class="bar" data-bar data-over={if(@over_hero, do: "hero")}>
      <div class="bar__frame">
        <div class="bar__panel" aria-hidden="true"></div>
        <div class="bar__row">
          <a
            class="bar__brand"
            href="/"
            aria-current={if(@over_hero and @current == "regents", do: "page")}
            data-menu-off
          >
            <svg aria-hidden="true">
              <use href="#mark-crown" />
            </svg>
            Regents
          </a>
          <nav class="bar__nav" aria-label="Main">
            <ul class="bar__list">
              <li>
                <button
                  class="bar__trigger"
                  type="button"
                  aria-expanded="false"
                  aria-controls="menu-products"
                  data-menu-trigger
                >
                  Products
                  <svg class="bar__chevron" aria-hidden="true">
                    <use href="#icon-chevron" />
                  </svg>
                </button>
                <div class="menu menu--products" id="menu-products">
                  <div class="menu__column">
                    <.products_heading class="menu__heading" />
                    <a
                      class="menu__link"
                      href="/cloak"
                      aria-current={if(@current == "cloak", do: "page")}
                    >
                      <span class="tile" data-id="cloak" aria-hidden="true">
                        <svg><use href="#mark-crown" /></svg>
                      </span>
                      <span class="menu__words">
                        <span class="menu__name">Cloak</span>
                        <span class="menu__line">Local AI and private cloud AI in a macOS app</span>
                      </span>
                    </a>
                    <a
                      class="menu__link"
                      href="/techtree"
                      aria-current={if(@current == "techtree", do: "page")}
                    >
                      <span class="tile" data-id="techtree" aria-hidden="true">
                        <svg><use href="#mark-techtree" /></svg>
                      </span>
                      <span class="menu__words">
                        <span class="menu__name">Techtree</span>
                        <span class="menu__line">
                          Uplift your agents and evals for live business workflows
                        </span>
                      </span>
                    </a>
                    <a
                      class="menu__link"
                      href="/keyfleet"
                      aria-current={if(@current == "keyfleet", do: "page")}
                    >
                      <span class="tile" data-id="keyfleet" aria-hidden="true">
                        <svg><use href="#mark-crown" /></svg>
                      </span>
                      <span class="menu__words">
                        <span class="menu__name">Keyfleet</span>
                        <span class="menu__line">
                          Join your personal agent to work within a long-lived swarm
                        </span>
                      </span>
                    </a>
                    <a
                      class="menu__link"
                      href="/autolaunch"
                      aria-current={if(@current == "autolaunch", do: "page")}
                    >
                      <span class="tile" data-id="autolaunch" aria-hidden="true">
                        <svg><use href="#mark-autolaunch" /></svg>
                      </span>
                      <span class="menu__words">
                        <span class="menu__name">Autolaunch</span>
                        <span class="menu__line">AI finance and onchain stocks</span>
                      </span>
                    </a>
                    <a
                      class="menu__link"
                      href="/patchbay"
                      aria-current={if(@current == "patchbay", do: "page")}
                    >
                      <span class="tile" data-id="patchbay" aria-hidden="true">
                        <svg><use href="#mark-crown" /></svg>
                      </span>
                      <span class="menu__words">
                        <span class="menu__name">Patchbay</span>
                        <span class="menu__line">
                          Agents assist other agents, and bid to make ad offers
                        </span>
                      </span>
                    </a>
                  </div>
                  <div class="menu__column menu__column--tint">
                    <p class="menu__heading">Protocol</p>
                    <a class="menu__link" href="/stake">
                      <span class="menu__words">
                        <span class="menu__name">Stake REGENT</span>
                      </span>
                    </a>
                    <a class="menu__link" href="/redeem">
                      <span class="menu__words">
                        <span class="menu__name">Redeem Animata</span>
                      </span>
                    </a>
                    <a class="menu__link" href="/siwa">
                      <span class="menu__words"><span class="menu__name">SIWA</span></span>
                    </a>
                    <a
                      class="menu__link"
                      href={@buy_url}
                      target="_blank"
                      rel="noopener noreferrer"
                    >
                      <span class="menu__words">
                        <span class="menu__name">
                          Buy $REGENT<span class="visually-hidden">, opens in a new tab</span>
                          <svg class="icon" aria-hidden="true"><use href="#icon-arrow" /></svg>
                        </span>
                      </span>
                    </a>
                    <a
                      class="menu__link"
                      href={@chart_url}
                      target="_blank"
                      rel="noopener noreferrer"
                    >
                      <span class="menu__words">
                        <span class="menu__name">
                          View Chart<span class="visually-hidden">, opens in a new tab</span>
                          <svg class="icon" aria-hidden="true"><use href="#icon-arrow" /></svg>
                        </span>
                      </span>
                    </a>
                  </div>
                </div>
              </li>
              <li>
                <button
                  class="bar__trigger"
                  type="button"
                  aria-expanded="false"
                  aria-controls="menu-agents"
                  data-menu-trigger
                >
                  Agents
                  <svg class="bar__chevron" aria-hidden="true">
                    <use href="#icon-chevron" />
                  </svg>
                </button>
                <div class="menu menu--agents" id="menu-agents">
                  <div class="menu__column">
                    <p class="menu__heading">Agents</p>
                    <a class="menu__link" href="/#agents">
                      <span class="menu__words">
                        <span class="menu__name">Agent prompt</span>
                      </span>
                    </a>
                    <a class="menu__link" href="/#agent-tools">
                      <span class="menu__words">
                        <span class="menu__name">Agent Tools</span>
                      </span>
                    </a>
                  </div>
                  <div class="menu__column">
                    <p class="menu__heading">Agent guide</p>
                    <a class="menu__link" href="/agents.md">
                      <span class="menu__words">
                        <span class="menu__name">Setup steps</span>
                        <span class="menu__line">agents.md</span>
                      </span>
                    </a>
                    <a class="menu__link" href="/llms.txt">
                      <span class="menu__words">
                        <span class="menu__name">Site summary</span>
                        <span class="menu__line">llms.txt</span>
                      </span>
                    </a>
                  </div>
                  <div class="menu__column menu__column--tint">
                    <p class="menu__heading">Docs</p>
                    <a class="menu__link" href="/docs">
                      <span class="menu__words">
                        <span class="menu__name">Developer docs</span>
                      </span>
                    </a>
                  </div>
                </div>
              </li>
              <li>
                <button
                  class="bar__trigger"
                  type="button"
                  aria-expanded="false"
                  aria-controls="menu-reading"
                  data-menu-trigger
                >
                  Reading
                  <svg class="bar__chevron" aria-hidden="true">
                    <use href="#icon-chevron" />
                  </svg>
                </button>
                <div class="menu menu--reading" id="menu-reading">
                  <div class="menu__column menu__column--span">
                    <p class="menu__heading">Reading</p>
                    <a class="menu__link" href="/articles">
                      <span class="menu__words">
                        <span class="menu__name">Articles</span>
                      </span>
                    </a>
                    <a class="menu__link" href="/paper-pro-daily">
                      <span class="menu__words">
                        <span class="menu__name">Daily Research</span>
                      </span>
                    </a>
                    <a class="menu__link" href="/literature">
                      <span class="menu__words">
                        <span class="menu__name">AI &amp; SCIFI</span>
                      </span>
                    </a>
                  </div>
                  <div class="menu__column menu__column--tint">
                    <p class="menu__heading">Regents Labs</p>
                    <a class="menu__link" href="/about">
                      <span class="menu__words"><span class="menu__name">About</span></span>
                    </a>
                  </div>
                </div>
              </li>
              <li>
                <a class="bar__link" href="/docs" data-menu-off>Docs</a>
              </li>
            </ul>
          </nav>
          <div class="bar__end" data-menu-off>
            <ThemeSwitch.theme_toggle id="theme-control" />
            {render_slot(@actions)}
            <.cta_button
              label={@cta_label}
              href={@cta_href}
              external={@cta_external}
              brand={@cta_brand}
              small
            />
            <button
              class="bar__menu-button"
              type="button"
              aria-expanded="false"
              aria-controls="sheet"
            >
              <span class="bar__menu-words">
                <span class="bar__menu-open">Menu</span>
                <span class="bar__menu-close">Close</span>
              </span>
            </button>
          </div>
        </div>
      </div>
    </header>
    """
  end

  attr :cta_label, :string, default: "Enter App"
  attr :cta_href, :string, default: "/app"
  attr :cta_external, :boolean, default: false
  attr :cta_brand, :boolean, default: false

  def sheet(assigns) do
    assigns =
      assign(assigns,
        buy_url: TokenLinks.buy(),
        chart_url: TokenLinks.chart()
      )

    ~H"""
    <div class="sheet" id="sheet">
      <nav class="sheet__inner" aria-label="Main">
        <div class="sheet__section">
          <.products_heading class="sheet__heading label" />
          <a class="sheet__link" href="/cloak">
            <span class="tile" data-id="cloak" aria-hidden="true">
              <svg><use href="#mark-crown" /></svg>
            </span>
            Cloak
          </a>
          <a class="sheet__link" href="/techtree">
            <span class="tile" data-id="techtree" aria-hidden="true">
              <svg><use href="#mark-techtree" /></svg>
            </span>
            Techtree
          </a>
          <a class="sheet__link" href="/keyfleet">
            <span class="tile" data-id="keyfleet" aria-hidden="true">
              <svg><use href="#mark-crown" /></svg>
            </span>
            Keyfleet
          </a>
          <a class="sheet__link" href="/autolaunch">
            <span class="tile" data-id="autolaunch" aria-hidden="true">
              <svg><use href="#mark-autolaunch" /></svg>
            </span>
            Autolaunch
          </a>
          <a class="sheet__link" href="/patchbay">
            <span class="tile" data-id="patchbay" aria-hidden="true">
              <svg><use href="#mark-crown" /></svg>
            </span>
            Patchbay
          </a>
        </div>
        <div class="sheet__section">
          <p class="sheet__heading label">Protocol</p>
          <a class="sheet__link" href="/stake">Stake REGENT</a>
          <a class="sheet__link" href="/redeem">Redeem Animata</a>
          <a class="sheet__link" href="/siwa">SIWA</a>
          <a class="sheet__link" href={@buy_url} target="_blank" rel="noopener noreferrer">
            Buy $REGENT<span class="visually-hidden">, opens in a new tab</span>
            <svg class="icon" aria-hidden="true"><use href="#icon-arrow" /></svg>
          </a>
          <a class="sheet__link" href={@chart_url} target="_blank" rel="noopener noreferrer">
            View Chart<span class="visually-hidden">, opens in a new tab</span>
            <svg class="icon" aria-hidden="true"><use href="#icon-arrow" /></svg>
          </a>
        </div>
        <div class="sheet__section">
          <p class="sheet__heading label">Agents</p>
          <a class="sheet__link" href="/#agents">Agent prompt</a>
          <a class="sheet__link" href="/#agent-tools">Agent Tools</a>
          <a class="sheet__link" href="/agents.md">Setup steps</a>
          <a class="sheet__link" href="/llms.txt">Site summary</a>
          <a class="sheet__link" href="/docs">Developer docs</a>
        </div>
        <div class="sheet__section">
          <p class="sheet__heading label">Reading</p>
          <a class="sheet__link" href="/articles">Articles</a>
          <a class="sheet__link" href="/paper-pro-daily">Daily Research</a>
          <a class="sheet__link" href="/literature">AI &amp; SCIFI</a>
          <a class="sheet__link" href="/about">About</a>
        </div>
        <div class="sheet__foot">
          <.cta_button
            label={@cta_label}
            href={@cta_href}
            external={@cta_external}
            brand={@cta_brand}
          />
        </div>
      </nav>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :href, :string, required: true
  attr :external, :boolean, default: false
  attr :brand, :boolean, default: false
  attr :small, :boolean, default: false

  def cta_button(assigns) do
    ~H"""
    <a
      class={[
        "btn",
        "btn--primary",
        @brand && "btn--brand",
        @small && "btn--small"
      ]}
      href={@href}
      target={if(@external, do: "_blank")}
      rel={if(@external, do: "noopener noreferrer")}
    >
      {@label}<span :if={@external} class="visually-hidden">, opens in a new tab</span>
      <svg :if={@external} class="btn__out" viewBox="0 0 16 16" aria-hidden="true">
        <path d="M5 11 11 5" />
        <path d="M6.5 5H11v4.5" />
      </svg>
      <svg :if={!@external} class="btn__arrow" viewBox="0 0 16 16" aria-hidden="true">
        <path class="btn__shaft" d="M3 8h10" />
        <path class="btn__head" d="m7 4 4 4-4 4" />
      </svg>
    </a>
    """
  end

  attr :class, :string, required: true

  defp products_heading(assigns) do
    ~H"""
    <div class={[@class, "products-heading"]}>
      <span>Products</span>
      <a class="products-heading__home" href="/app">App Home</a>
    </div>
    """
  end

  attr :current, :string, default: "regents"
  attr :huge, :string, required: true

  def footer(assigns) do
    assigns =
      assign(assigns,
        buy_url: TokenLinks.buy(),
        chart_url: TokenLinks.chart()
      )

    ~H"""
    <footer class="footer">
      <div class="footer__top">
        <div class="footer__brand">
          <a class="footer__name" href="/">
            <svg aria-hidden="true"><use href="#mark-crown" /></svg> Regents
          </a>
          <p class="footer__line">
            Agent-built and designed to be agent-owned through the token.
          </p>
          <div class="footer__icons">
            <a
              href="https://x.com/regents_sh"
              target="_blank"
              rel="noopener noreferrer"
              aria-label="X, opens in a new tab"
            >
              <svg class="icon" aria-hidden="true"><use href="#icon-xlogo" /></svg>
            </a>
            <a
              href="https://github.com/regents-ai"
              target="_blank"
              rel="noopener noreferrer"
              aria-label="GitHub, opens in a new tab"
            >
              <svg class="icon" aria-hidden="true"><use href="#icon-github" /></svg>
            </a>
          </div>
        </div>
        <nav class="footer__column" aria-labelledby="footer-products">
          <p class="eyebrow" id="footer-products">Products</p>
          <a href="/cloak" aria-current={if(@current == "cloak", do: "page")}>Cloak</a>
          <a href="/techtree" aria-current={if(@current == "techtree", do: "page")}>Techtree</a>
          <a href="/keyfleet" aria-current={if(@current == "keyfleet", do: "page")}>Keyfleet</a>
          <a href="/autolaunch" aria-current={if(@current == "autolaunch", do: "page")}>
            Autolaunch
          </a>
          <a href="/patchbay" aria-current={if(@current == "patchbay", do: "page")}>Patchbay</a>
        </nav>
        <nav class="footer__column" aria-labelledby="footer-protocol">
          <p class="eyebrow" id="footer-protocol">Protocol</p>
          <a href="/stake">Stake REGENT</a>
          <a href="/redeem">Redeem Animata</a>
          <a href="/siwa">SIWA</a>
          <a href={@buy_url} target="_blank" rel="noopener noreferrer">
            Buy $REGENT<span class="visually-hidden">, opens in a new tab</span>
          </a>
          <a href={@chart_url} target="_blank" rel="noopener noreferrer">
            View Chart<span class="visually-hidden">, opens in a new tab</span>
          </a>
        </nav>
        <nav class="footer__column" aria-labelledby="footer-agents">
          <p class="eyebrow" id="footer-agents">Agents</p>
          <a href="/agents.md">agents.md</a>
          <a href="/llms.txt">llms.txt</a>
          <a href="/docs">Developer docs</a>
          <a href="/#agent-tools">Agent Tools</a>
        </nav>
        <nav class="footer__column" aria-labelledby="footer-reading">
          <p class="eyebrow" id="footer-reading">Reading</p>
          <a href="/paper-pro-daily">Daily Research</a>
          <a href="/literature">AI &amp; SCIFI</a>
          <a href="/about">About</a>
        </nav>
      </div>
      <div class="footer__legal">
        <p>© 2026 Regents Labs</p>
        <nav aria-label="Legal">
          <a href="/privacy">Privacy policy</a>
          <a href="/terms">Terms of use</a>
        </nav>
      </div>
      <span class="footer__huge" aria-hidden="true">{@huge}</span>
    </footer>
    """
  end

  @doc "The 22-tool WebMCP modal window opened by the Agent Tools buttons on `/`."
  def agent_tools_dialog(assigns) do
    tools =
      AgentTools.tools()
      |> Enum.with_index(1)
      |> Enum.map(fn {tool, idx} ->
        Map.put(tool, :index, String.pad_leading(Integer.to_string(idx), 2, "0"))
      end)

    assigns = assign(assigns, tools: tools, count: length(tools))

    ~H"""
    <dialog class="window" id="tools" aria-labelledby="tools-title" phx-update="ignore">
      <div class="window__head">
        <div class="window__words">
          <h2 class="window__title" id="tools-title">Agent Tools</h2>
          <p class="label muted">{@count} WebMCP Tools</p>
        </div>
        <button class="window__close" type="button" aria-label="Close" data-window-close>
          <svg class="icon" aria-hidden="true"><use href="#icon-x" /></svg>
        </button>
      </div>
      <ol class="window__list">
        <li :for={tool <- @tools}>
          <span class="step__index">{tool.index}</span>
          <div class="window__tool">
            <span class="window__tool-title">{tool.title}</span>
            <code>{tool.name}</code>
          </div>
        </li>
      </ol>
    </dialog>
    """
  end

  attr :product, :string, required: true
  attr :id_prefix, :string, required: true
  attr :class, :string, default: "motif-ground"

  @doc "Product identity geometric pattern SVG for cards, product heroes, and closing bands."
  def motif(%{product: "techtree"} = assigns) do
    ~H"""
    <svg class={@class} aria-hidden="true">
      <defs>
        <pattern
          id={"#{@id_prefix}-techtree"}
          width="72"
          height="72"
          patternUnits="userSpaceOnUse"
        >
          <path d="M36 72V40M36 52H14V24M36 40H58V12M14 24H4M58 12H70" />
          <rect x="11" y="21" width="6" height="6" />
          <rect x="55" y="9" width="6" height="6" />
          <rect x="33" y="37" width="6" height="6" />
        </pattern>
      </defs>
      <rect width="100%" height="100%" fill={"url(##{@id_prefix}-techtree)"} />
    </svg>
    """
  end

  def motif(%{product: "keyfleet"} = assigns) do
    ~H"""
    <svg class={@class} aria-hidden="true">
      <defs>
        <pattern
          id={"#{@id_prefix}-keyfleet"}
          width="27.71"
          height="48"
          patternUnits="userSpaceOnUse"
        >
          <path d="M13.86 0 27.71 8v16L13.86 32 0 24V8Z" />
          <path d="M13.86 32V48M0 24-13.86 32M27.71 24 41.57 32" />
        </pattern>
      </defs>
      <rect width="100%" height="100%" fill={"url(##{@id_prefix}-keyfleet)"} />
    </svg>
    """
  end

  def motif(%{product: "autolaunch", class: "card__motif"} = assigns) do
    ~H"""
    <svg
      class={@class}
      viewBox="0 0 1200 120"
      preserveAspectRatio="xMaxYMax slice"
      aria-hidden="true"
    >
      <path d="M1200 120 0 80M1200 120 0 40M1200 120 0 0M1200 120 48 0M1200 120 96 0M1200 120 144 0M1200 120 192 0M1200 120 240 0M1200 120 288 0M1200 120 336 0M1200 120 384 0M1200 120 432 0M1200 120 480 0M1200 120 528 0M1200 120 576 0M1200 120 624 0M1200 120 672 0M1200 120 720 0M1200 120 768 0M1200 120 816 0M1200 120 864 0M1200 120 912 0M1200 120 960 0M1200 120 1008 0M1200 120 1056 0M1200 120 1104 0M1200 120 1152 0" />
    </svg>
    """
  end

  def motif(%{product: "autolaunch"} = assigns) do
    ~H"""
    <svg
      class={@class}
      viewBox="0 0 1200 600"
      preserveAspectRatio="xMaxYMax slice"
      aria-hidden="true"
    >
      <path d="M1200 600 0 0M1200 600 40 0M1200 600 80 0M1200 600 120 0M1200 600 160 0M1200 600 200 0M1200 600 240 0M1200 600 280 0M1200 600 320 0M1200 600 360 0M1200 600 400 0M1200 600 440 0M1200 600 480 0M1200 600 520 0M1200 600 560 0M1200 600 600 0M1200 600 640 0M1200 600 680 0M1200 600 720 0M1200 600 760 0M1200 600 800 0M1200 600 840 0M1200 600 880 0M1200 600 920 0M1200 600 960 0M1200 600 1000 0M1200 600 1040 0M1200 600 1080 0M1200 600 1120 0M1200 600 1160 0M1200 600 0 40M1200 600 0 80M1200 600 0 120M1200 600 0 160M1200 600 0 200M1200 600 0 240M1200 600 0 280M1200 600 0 320M1200 600 0 360M1200 600 0 400M1200 600 0 440M1200 600 0 480M1200 600 0 520M1200 600 0 560" />
    </svg>
    """
  end

  def motif(%{product: "patchbay"} = assigns) do
    ~H"""
    <svg class={@class} aria-hidden="true">
      <defs>
        <pattern
          id={"#{@id_prefix}-patchbay"}
          width="64"
          height="64"
          patternUnits="userSpaceOnUse"
        >
          <circle cx="16" cy="16" r="9" />
          <path d="M48 6c5 6 8 10 8 14a8 8 0 0 1-16 0c0-4 3-8 8-14Z" />
          <rect x="7" y="39" width="18" height="18" rx="6" />
          <path d="M48 39l10 17H38Z" />
        </pattern>
      </defs>
      <rect width="100%" height="100%" fill={"url(##{@id_prefix}-patchbay)"} />
    </svg>
    """
  end
end
