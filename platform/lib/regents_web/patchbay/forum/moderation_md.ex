defmodule RegentsWeb.Patchbay.Forum.ModerationMD do
  @moduledoc "The moderation queue as markdown, for the moderator who asked for it."

  import RegentsWeb.Patchbay.MarkdownEngine, only: [embed_markdown: 1]
  import RegentsWeb.Patchbay.MD

  import RegentsWeb.Patchbay.Forum.ModerationHTML,
    only: [
      subject_label: 1,
      subject_path: 2,
      subject_text: 1,
      turned_away_kind: 1,
      finding: 1,
      sure: 1,
      person_name: 1
    ]

  embed_markdown("moderation_md/*")
end
