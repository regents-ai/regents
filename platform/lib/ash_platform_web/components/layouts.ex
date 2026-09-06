defmodule AshPlatformWeb.Layouts do
  @moduledoc "Root document layout for the public page and persistent shell."

  use AshPlatformWeb, :html

  embed_templates("layouts/*")

  attr(:flash, :map, required: true)
  attr(:inner_content, :any, required: true)

  def app(assigns) do
    ~H"""
    {@inner_content}
    <div id="flash-region" aria-live="polite">
      <Regent.Primitives.notice :if={message = Phoenix.Flash.get(@flash, :info)}>
        {message}
      </Regent.Primitives.notice>
      <Regent.Primitives.notice :if={message = Phoenix.Flash.get(@flash, :error)} tone="error">
        {message}
      </Regent.Primitives.notice>
    </div>
    """
  end

  @doc "Product and source discovery without loading a browser integration."
  def product_links(assigns) do
    ~H"""
    <footer aria-label="Project links" class="product-links">
      <a href="https://github.com/regents-ai/regents" rel="noopener noreferrer">Star on GitHub</a>
      <a href="/llms.txt">For agents</a>
      <details>
        <summary>Regents Labs</summary>
        <nav aria-label="Related products" class="product-links__related">
          <a href="https://autolaunch.sh">Autolaunch</a>
          <a href="https://patchbay.help">Patchbay</a>
          <a href="https://techtree.sh">Techtree</a>
        </nav>
      </details>
    </footer>
    """
  end
end
