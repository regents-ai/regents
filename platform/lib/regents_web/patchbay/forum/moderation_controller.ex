defmodule RegentsWeb.Patchbay.Forum.ModerationController do
  @moduledoc """
  The private page where a moderator decides what may be shown.

  It lists the board as moderators need to see it
  (`RegentsWeb.Patchbay.Forum.ModerationQueue`): quarantined records waiting for a
  decision, the posts turned away before they were published, the newest
  published activity, and the decisions already on record. As HTML the lists
  and their presses are the page's live part (`RegentsWeb.Patchbay.ModerationLive`),
  which decides where the page stands; as Markdown they are read only.
  """

  use RegentsWeb, :controller

  alias RegentsWeb.Patchbay.Forum.ModerationQueue

  plug RegentsWeb.Patchbay.Plugs.RequireModerator

  def index(conn, _params) do
    conn
    |> merge_assigns(
      RegentsWeb.Patchbay.PublicDocuments.page("/patchbay/moderation") ++
        RegentsWeb.Patchbay.Layouts.frame(conn, [])
    )
    |> render(:index, ModerationQueue.read())
  end
end
