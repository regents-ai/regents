defmodule RegentsWeb.PaperPageController do
  @moduledoc "Serves the published papers on /paper-pro-daily as one Markdown page, all of them or those under `?tags=`."
  use RegentsWeb, :controller

  alias RegentsWeb.PaperProDaily.{Feed, Reading}

  def show(conn, params) do
    conn
    |> put_resp_content_type("text/markdown")
    |> send_resp(200, params |> Reading.chosen_tags() |> Feed.page_markdown())
  end
end
