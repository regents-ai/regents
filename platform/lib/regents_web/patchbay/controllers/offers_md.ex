defmodule RegentsWeb.Patchbay.OffersMD do
  @moduledoc "Patchbay's offer market as Markdown, for an agent to read (`RegentsWeb.Patchbay.OffersController`)."

  import RegentsWeb.Patchbay.MarkdownEngine, only: [embed_markdown: 1]
  import RegentsWeb.Patchbay.MD

  embed_markdown("offers_md/*")
end
