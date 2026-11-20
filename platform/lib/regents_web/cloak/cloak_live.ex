defmodule RegentsWeb.Cloak.CloakLive do
  @moduledoc """
  The `/cloak` product page: the founder's approved words (`RegentsWeb.Cloak`)
  and the Mac app's Download, a plain link to the newest signed build.
  """
  use RegentsWeb, :html

  alias RegentsWeb.Cloak

  def page(assigns) do
    ~H"""
    <section id="cloak-page" class="product-page cloak-page" aria-labelledby="product-heading">
      <header class="product-heading rg-panel rg-panel--surface rg-panel__body">
        <p class="product-kicker cloak-page__address">{Cloak.top_line()}</p>
        <h1 id="product-heading" tabindex="-1">{Cloak.heading()}</h1>
        <p class="product-lede">{Cloak.note()}</p>
      </header>

      <ul class="product-proofs" role="list">
        <li :for={{word, sentence} <- Cloak.points()}>
          <Regent.Structure.panel class="product-proof cloak-point rg-panel__body">
            <p><strong>{word}</strong> {sentence}</p>
          </Regent.Structure.panel>
        </li>
      </ul>

      <div class="product-columns">
        <Regent.Structure.panel class="product-column rg-panel__body">
          <h2 class="product-kicker">About</h2>
          <p>{Cloak.about()}</p>
        </Regent.Structure.panel>
        <Regent.Structure.panel class="product-column cloak-caution rg-panel__body">
          <p>{Cloak.caution()}</p>
        </Regent.Structure.panel>
      </div>

      <div class="product-columns">
        <Regent.Structure.panel class="product-column rg-panel__body">
          <h2 class="product-kicker">Needs</h2>
          <p>{Cloak.needs()}</p>
        </Regent.Structure.panel>
        <Regent.Structure.panel id="cloak-install" class="product-column rg-panel__body">
          <h2 class="product-kicker">Install</h2>
          <ol class="cloak-steps">
            <li :for={step <- Cloak.install()}>{step}</li>
          </ol>
          <div class="cloak-download">
            <a id="cloak-download" class="cloak-download__button" href={Cloak.download()}>
              <.apple_logo />
              <span>Download</span>
            </a>
            <span class="cloak-download__note">{Cloak.updates()}</span>
          </div>
        </Regent.Structure.panel>
      </div>

      <p class="cloak-page__feedback">{Cloak.feedback()}</p>
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
