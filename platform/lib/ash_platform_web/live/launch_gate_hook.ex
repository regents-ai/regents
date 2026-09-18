defmodule AshPlatformWeb.Live.LaunchGateHook do
  @moduledoc """
  Keeps product LiveViews closed while the launch gate is closed. It covers
  mounts that reach the socket without a fresh request: reconnects and live
  navigation from a page loaded before the gate closed.

  The mount check alone would let a page opened while the gate was open keep
  moving between the routes it covers, since those moves patch the running
  LiveView instead of asking for a new page, so every navigation is checked too.
  """

  use AshPlatformWeb, :verified_routes

  import Phoenix.LiveView, only: [attach_hook: 4, redirect: 2]

  alias AshPlatformWeb.Plugs.LaunchGate

  def on_mount(:default, _params, _session, socket) do
    with {:cont, socket} <- app_gate(socket) do
      {:cont, attach_hook(socket, :launch_gate, :handle_params, &gate_navigation/3)}
    end
  end

  defp gate_navigation(_params, _uri, socket), do: app_gate(socket)

  defp app_gate(socket) do
    if LaunchGate.app_surfaces_enabled?(),
      do: {:cont, socket},
      else: {:halt, redirect(socket, to: ~p"/")}
  end
end
