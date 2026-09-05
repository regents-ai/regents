defmodule AshPlatformWeb.Live.LaunchGateHook do
  @moduledoc """
  Keeps product LiveViews closed while the launch gate is closed, and keeps the
  Autolaunch pages closed while their own separate switch is closed. Both cover
  mounts that reach the socket without a fresh request: reconnects and live
  navigation from a page loaded before the gate closed.

  The mount check alone would let a page opened while a gate was open keep
  moving between the routes it covers, since those moves patch the running
  LiveView instead of asking for a new page, so every navigation is checked too.
  """

  use AshPlatformWeb, :verified_routes

  import Phoenix.LiveView, only: [attach_hook: 4, redirect: 2]

  alias AshPlatformWeb.Plugs.LaunchGate

  def on_mount(:default, _params, _session, socket) do
    with {:cont, socket} <- app_gate(socket),
         {:cont, socket} <-
           autolaunch_gate(socket, autolaunch_action?(socket.assigns.live_action)) do
      {:cont, attach_hook(socket, :launch_gate, :handle_params, &gate_navigation/3)}
    end
  end

  defp gate_navigation(_params, uri, socket) do
    with {:cont, socket} <- app_gate(socket),
         do: autolaunch_gate(socket, autolaunch_path?(URI.parse(uri).path))
  end

  defp app_gate(socket), do: gate(socket, LaunchGate.app_surfaces_enabled?(), ~p"/")

  defp autolaunch_gate(socket, false), do: {:cont, socket}

  defp autolaunch_gate(socket, true),
    do: gate(socket, LaunchGate.autolaunch_surfaces_enabled?(), ~p"/app")

  defp gate(socket, true, _destination), do: {:cont, socket}
  defp gate(socket, false, destination), do: {:halt, redirect(socket, to: destination)}

  defp autolaunch_action?(live_action),
    do: live_action |> Atom.to_string() |> String.starts_with?("autolaunch")

  defp autolaunch_path?(path), do: String.starts_with?(path, "/autolaunch")
end
