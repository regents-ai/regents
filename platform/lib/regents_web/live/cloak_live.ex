defmodule RegentsWeb.CloakLive do
  @moduledoc """
  The `/cloak` product page. Its one action is the Mac app's download, which
  stays off, with the reason beside it, until a signed release exists.
  """
  use RegentsWeb, :html

  alias RegentsWeb.Cloak
  alias RegentsWeb.HomeLive
  alias RegentsWeb.ProductLive

  def page(assigns) do
    assigns =
      assign(assigns,
        cards: Cloak.cards(),
        protections:
          Enum.map(Cloak.protections(), &Map.merge(&1, %{status: :planned, link: nil})),
        limits: Cloak.limits()
      )

    ~H"""
    <section id="cloak-page" class="product-page" aria-labelledby="product-heading">
      <header class="product-heading rg-panel rg-panel--surface rg-panel__body">
        <p class="product-kicker">Regents Cloak</p>
        <h1 id="product-heading" tabindex="-1">The private agent stack, ready to run.</h1>
        <p class="product-lede">Install the complete setup through one Mac app.</p>
        <div class="product-actions cloak-download">
          <button
            type="button"
            class="cloak-download__button"
            disabled
            aria-describedby="cloak-download-soon"
          >
            <.apple_logo />
            <span>Download for Mac</span>
          </button>
          <span id="cloak-download-soon" class="cloak-download__soon">Coming soon</span>
        </div>
      </header>

      <ProductLive.cards cards={@cards} />

      <Regent.Structure.section_bar class="rg-support-band">
        <h2 id="protections" class="rg-section-bar__label">Protections</h2>
      </Regent.Structure.section_bar>
      <ul class="product-proofs" aria-label="Protections">
        <li :for={protection <- @protections}>
          <Regent.Structure.panel class="product-proof rg-panel__body">
            <h3>{protection.title}</h3>
            <p>{protection.copy}</p>
            <div class="product-proof__status"><HomeLive.proof_status proof={protection} /></div>
          </Regent.Structure.panel>
        </li>
      </ul>

      <div class="product-columns">
        <Regent.Structure.panel class="product-column rg-panel__body">
          <h2 class="product-kicker">Limits</h2>
          <ul class="product-audience">
            <li :for={limit <- @limits}>{limit}</li>
          </ul>
        </Regent.Structure.panel>
        <Regent.Structure.panel class="product-column rg-panel__body">
          <h2 class="product-kicker">Origin</h2>
          <p>The private setup Vitalik Buterin described on 16 October, packaged for the Mac.</p>
          <nav class="product-family__links" aria-label="Origin">
            <ProductLive.external href={Cloak.post()}>Read the post</ProductLive.external>
          </nav>
        </Regent.Structure.panel>
      </div>
    </section>
    """
  end

  # The Apple mark, filled in the button's ink. The site's icon set (Lucide) has
  # only the fruit.
  defp apple_logo(assigns) do
    ~H"""
    <svg
      class="cloak-download__logo"
      viewBox="0 0 24 24"
      aria-hidden="true"
      focusable="false"
      fill="currentColor"
    >
      <path d="M12.152 6.896c-.948 0-2.415-1.078-3.96-1.04-2.04.027-3.91 1.183-4.961 3.014-2.117 3.675-.546 9.103 1.519 12.09 1.013 1.454 2.208 3.09 3.792 3.039 1.52-.065 2.09-.987 3.935-.987 1.831 0 2.35.987 3.96.948 1.637-.026 2.676-1.48 3.676-2.948 1.156-1.688 1.636-3.325 1.662-3.415-.039-.013-3.182-1.221-3.22-4.857-.026-3.04 2.48-4.494 2.597-4.559-1.429-2.09-3.623-2.324-4.39-2.376-2-.156-3.675 1.09-4.61 1.09zM15.53 3.83c.843-1.012 1.4-2.427 1.245-3.83-1.207.052-2.662.805-3.532 1.818-.78.896-1.454 2.338-1.273 3.714 1.338.104 2.715-.688 3.559-1.701" />
    </svg>
    """
  end
end
