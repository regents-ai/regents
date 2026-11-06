defmodule RegentsWeb.Live.AdminHook do
  @moduledoc false
  import Phoenix.LiveView, only: [attach_hook: 4, redirect: 2]

  alias RegentsWeb.ShellLive.Identity

  def on_mount(:default, _params, _session, socket) do
    with {:cont, socket} <- admit(socket) do
      {:cont,
       socket
       |> attach_hook(:admin_params, :handle_params, fn _, _, socket -> admit(socket) end)
       |> attach_hook(:admin_events, :handle_event, fn _, _, socket -> admit(socket) end)}
    end
  end

  defp admit(%{assigns: %{live_action: :articles_admin}} = socket) do
    if Regents.Blog.admin?(Identity.current_account(socket.assigns.access_context)),
      do: {:cont, socket},
      else: {:halt, redirect(socket, to: "/articles")}
  end

  # Anyone but the site's admins gets the not-found page.
  defp admit(%{assigns: %{live_action: :pictures_admin}} = socket) do
    if Regents.admin?(Identity.current_account(socket.assigns.access_context)),
      do: {:cont, socket},
      else: raise(RegentsWeb.NotFoundError)
  end

  defp admit(socket), do: {:cont, socket}
end
