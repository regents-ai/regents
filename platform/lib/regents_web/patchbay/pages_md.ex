defmodule RegentsWeb.Patchbay.PagesMD do
  @moduledoc "The help, about, privacy, terms, changelog, WebMCP, developer and agents pages as markdown."

  import RegentsWeb.Patchbay.MarkdownEngine, only: [embed_markdown: 1]
  import RegentsWeb.Patchbay.MD
  import RegentsWeb.Patchbay.PagesHTML, only: [effect_label: 1, surface_label: 1]

  embed_markdown("pages_md/*")
end
