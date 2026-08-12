defmodule AshPlatformWeb.Live.LaunchGateHook do
  @moduledoc """
  Keeps product LiveViews closed while the launch gate is closed, including
  mounts that reach the socket without a fresh request: reconnects and live
  navigation from a page loaded before the gate closed.

  The mount check alone would let a page opened while the gate was open keep
  moving between product routes, since those moves patch the running LiveView
  instead of asking for a new page, so every navigation is checked too.
  """

  use AshPlatformWeb, :verified_routes

  import Phoenix.LiveView, only: [attach_hook: 4, redirect: 2]

  alias AshPlatformWeb.Plugs.LaunchGate

  def on_mount(:default, _params, _session, socket) do
    with {:cont, socket} <- gate(socket, LaunchGate.app_surfaces_enabled?()) do
      {:cont, attach_hook(socket, :launch_gate, :handle_params, &gate_navigation/3)}
    end
  end

  defp gate_navigation(_params, _uri, socket),
    do: gate(socket, LaunchGate.app_surfaces_enabled?())

  defp gate(socket, true), do: {:cont, socket}
  defp gate(socket, false), do: {:halt, redirect(socket, to: ~p"/")}
end
