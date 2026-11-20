defmodule RegentsWeb.Techtree.PublicPagesController do
  @moduledoc """
  Security's sample report, a committed Markdown document, as a page in
  Techtree's frame.
  """

  use RegentsWeb, :controller

  alias RegentsWeb.Techtree.Layouts
  alias RegentsWeb.Techtree.PublicPagesHTML

  def show(conn, _params) do
    page = PublicPagesHTML.page(conn.request_path)

    render(conn, :show,
      page: page,
      page_title: page.title,
      page_description: Layouts.description(conn.request_path),
      current_path: conn.request_path
    )
  end
end
