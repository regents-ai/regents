defmodule AshPlatformWeb.SharedProfileController do
  use AshPlatformWeb, :controller

  def show(conn, _params) do
    access =
      case conn.assigns.current_human_account do
        nil -> AshPlatform.AccessContext.anonymous()
        account -> AshPlatform.AccessContext.human(account)
      end

    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_layout(html: {AshPlatformWeb.Layouts, :app})
    |> render(:show,
      page_title: "Profile",
      current_path: "/profile",
      account_control: AshPlatform.AccessContext.account_control(access)
    )
  end
end
