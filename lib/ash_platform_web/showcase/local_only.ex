defmodule AshPlatformWeb.Showcase.LocalOnly do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  @enabled Application.compile_env(:ash_platform, :local_showcase, false)

  def init(opts), do: opts

  def call(conn, _opts) do
    if @enabled and allowed?(conn.remote_ip, conn.host) do
      conn
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_header("x-robots-tag", "noindex, nofollow")
    else
      conn |> send_resp(404, "Not found") |> halt()
    end
  end

  def on_mount(:default, _params, _session, socket) do
    if Phoenix.LiveView.connected?(socket) do
      peer = Phoenix.LiveView.get_connect_info(socket, :peer_data)
      uri = Phoenix.LiveView.get_connect_info(socket, :uri)

      if @enabled and allowed?(peer && peer.address, uri && uri.host),
        do: {:cont, socket},
        else: {:halt, Phoenix.LiveView.redirect(socket, to: "/")}
    else
      {:cont, socket}
    end
  end

  def allowed?(address, host) when host in ["localhost", "127.0.0.1", "::1", "[::1]"],
    do: loopback?(address)

  def allowed?(_, _), do: false
  defp loopback?({127, _, _, _}), do: true
  defp loopback?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  defp loopback?(_), do: false
end
