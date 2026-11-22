defmodule RegentsWeb.Patchbay.TechtreeDiscussionHTML do
  @moduledoc "What a Techtree Result's discussion link shows when it cannot lead there yet."

  use RegentsWeb, :html

  import RegentsWeb.Patchbay.Forum.BoardHTML, only: [board_header: 1]

  embed_templates("techtree_discussion_html/*")
end
