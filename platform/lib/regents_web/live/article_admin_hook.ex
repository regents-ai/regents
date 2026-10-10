defmodule RegentsWeb.Live.ArticleAdminHook do
  @moduledoc false
  import Phoenix.LiveView, only: [attach_hook: 4, redirect: 2]

  def on_mount(:default, _params, _session, socket) do
    with {:cont, socket} <- admit(socket) do
      {:cont,
       socket
       |> attach_hook(:article_admin_params, :handle_params, fn _, _, socket -> admit(socket) end)
       |> attach_hook(:article_admin_events, :handle_event, fn _, _, socket -> admit(socket) end)}
    end
  end

  defp admit(%{assigns: %{live_action: :articles_admin}} = socket) do
    account = RegentsWeb.ShellLive.Identity.current_account(socket.assigns.access_context)

    if Regents.Blog.admin?(account),
      do: {:cont, socket},
      else: {:halt, redirect(socket, to: "/articles")}
  end

  defp admit(socket), do: {:cont, socket}
end
