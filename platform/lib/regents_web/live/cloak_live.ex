defmodule RegentsWeb.CloakLive do
  @moduledoc """
  The `/cloak` product page and the `/cloak/guide` setup guide. The download
  stays off, with the reason beside it, until a signed release exists.
  """
  use RegentsWeb, :html

  alias RegentsWeb.Cloak
  alias RegentsWeb.HomeLive
  alias RegentsWeb.ProductLive

  def page(assigns) do
    assigns =
      assign(assigns,
        protections:
          Enum.map(Cloak.protections(), &Map.merge(&1, %{status: :planned, link: nil})),
        limits: Cloak.limits(),
        agent_line: Cloak.agent_line()
      )

    ~H"""
    <section id="cloak-page" class="product-page" aria-labelledby="product-heading">
      <header class="product-heading rg-panel rg-panel--surface rg-panel__body">
        <p class="product-kicker">Regents Cloak</p>
        <h1 id="product-heading" tabindex="-1">The private agent stack, ready to run.</h1>
        <p class="product-lede">
          Install the complete setup through one Mac app—or ask your personal agent to do it for you.
        </p>
        <nav class="product-actions" aria-label="Regents Cloak">
          <span class="cloak-download">
            <Regent.Primitives.button disabled aria-describedby="cloak-download-soon">
              Download for Mac
            </Regent.Primitives.button>
            <span id="cloak-download-soon" class="cloak-download__soon">Coming soon</span>
          </span>
          <.link navigate={~p"/cloak/guide"} class="rg-button rg-button--secondary">
            <span class="rg-button__label">Set up with your agent</span>
          </.link>
        </nav>
      </header>

      <Regent.Structure.section_bar class="rg-support-band">
        <h2 class="rg-section-bar__label">Protections</h2>
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

      <Regent.Structure.panel class="product-family rg-panel__body">
        <p class="product-agent-line">
          <span class="product-kicker">Give this to your agent</span>
          <code>{@agent_line}</code>
        </p>
        <nav class="product-family__links" aria-label="Guide">
          <.link navigate={~p"/cloak/guide"}>Setup guide</.link>
        </nav>
      </Regent.Structure.panel>
    </section>
    """
  end

  def guide(assigns) do
    ~H"""
    <article id="cloak-guide" class="product-page">
      <Regent.Structure.panel class="cloak-guide rg-panel__body">
        {RegentsWeb.PublicDocuments.html(Cloak.guide_markdown())}
      </Regent.Structure.panel>
    </article>
    """
  end
end
