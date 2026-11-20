defmodule RegentsWeb.Patchbay.BlogMD do
  @moduledoc "The blog as markdown: the index as a list, a post as its own text."

  import RegentsWeb.Patchbay.MarkdownEngine, only: [embed_markdown: 1]
  import RegentsWeb.Patchbay.MD

  embed_markdown("blog_md/*")
end
