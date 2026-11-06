defmodule RegentsWeb.PaperPageController do
  @moduledoc "Serves every published paper on /paper-pro-daily as one Markdown page."
  use RegentsWeb, :controller

  alias RegentsWeb.PaperProDaily.Feed

  def show(conn, _params) do
    conn
    |> put_resp_content_type("text/markdown")
    |> send_resp(200, Feed.page_markdown())
  end
end
