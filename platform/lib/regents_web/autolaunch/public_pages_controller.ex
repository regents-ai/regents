defmodule RegentsWeb.Autolaunch.PublicPagesController do
  @moduledoc """
  Autolaunch's written pages (`RegentsWeb.Autolaunch.PublicDocuments`), each its
  committed Markdown shown as a page in Autolaunch's frame. A request for a page's
  Markdown is answered before the router; this shows the same document as HTML.
  The bar shows the account the session pipeline found, as the site's other pages
  do (`RegentsWeb.Live.Session`).
  """

  use RegentsWeb, :controller

  alias RegentsWeb.Autolaunch.PublicDocuments
  alias RegentsWeb.Live.Session

  def show(conn, _params) do
    path = conn.request_path
    page = PublicDocuments.page(path)
    %{markdown: markdown} = PublicDocuments.document(path)

    render(
      conn,
      :show,
      [
        document: PublicDocuments.html(markdown),
        current_path: path,
        account_control: conn |> get_session() |> Session.account_control()
      ] ++ page
    )
  end
end
