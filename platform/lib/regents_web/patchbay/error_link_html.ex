defmodule RegentsWeb.Patchbay.ErrorLinkHTML do
  @moduledoc "What an error's link shows when Patchbay has no post for that error yet."

  use RegentsWeb, :html

  import RegentsWeb.Patchbay.Chrome, only: [board_header: 1]

  embed_templates("error_link_html/*")
end
