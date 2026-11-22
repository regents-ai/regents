defmodule RegentsWeb.Autolaunch.UnavailableController do
  @moduledoc """
  The page a visitor reaches when a page is not offered where they are. The
  site's edge sends them here instead of its own refusal, so they stay inside
  the product shell, with the top bar and rail, and can carry on.
  """
  use RegentsWeb, :controller

  alias RegentsWeb.Autolaunch.PublicDocuments
  alias RegentsWeb.Live.Session

  def show(conn, _params) do
    render(
      conn,
      :show,
      [
        current_path: conn.request_path,
        account_control: conn |> get_session() |> Session.account_control()
      ] ++ PublicDocuments.page("/autolaunch/unavailable")
    )
  end
end
