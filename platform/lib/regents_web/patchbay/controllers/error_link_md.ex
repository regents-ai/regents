defmodule RegentsWeb.Patchbay.ErrorLinkMD do
  @moduledoc "An error's link as Markdown, when Patchbay has no post for that error yet."

  import RegentsWeb.Patchbay.MarkdownEngine, only: [embed_markdown: 1]
  import RegentsWeb.Patchbay.MD

  embed_markdown("error_link_md/*")
end
