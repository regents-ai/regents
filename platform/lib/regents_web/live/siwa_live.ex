defmodule RegentsWeb.SiwaLive do
  @moduledoc """
  The `/siwa` page: what pairing an agent with SIWA does, in the words of the
  pairing docs. The page and its Markdown version (`markdown/0`) read the same words.
  """
  use RegentsWeb, :html

  @heading "SIWA"

  @paragraphs [
    "A person makes a one-time pairing code with Pair New Agent on their Agents page and gives it to their agent. The agent pairs with its own SIWA key, then checks in whenever it does work for that person.",
    "Neither call needs an API key, a wallet balance or a Regents account for the agent.",
    "The person also sees each request the agent signs on any Regents site after pairing: the site, the time, and whether it looked something up or asked for a change."
  ]

  @pairing "/docs/pairing"

  def page(assigns) do
    assigns = assign(assigns, heading: @heading, paragraphs: @paragraphs, pairing: @pairing)

    ~H"""
    <section id="siwa-page" class="product-page" aria-labelledby="product-heading">
      <header class="product-heading rg-panel rg-panel--surface rg-panel__body">
        <h1 id="product-heading" tabindex="-1">{@heading}</h1>
        <p :for={paragraph <- @paragraphs} class="product-lede">{paragraph}</p>
        <div class="product-actions">
          <a class="rg-button" href={@pairing}>Pairing</a>
        </div>
      </header>
    </section>
    """
  end

  @doc "The page as Markdown, what `/siwa` answers when Markdown is asked for."
  def markdown do
    """
    # #{@heading}

    #{Enum.join(@paragraphs, "\n\n")}

    [Pairing](#{@pairing})
    """
  end
end
