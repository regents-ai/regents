defmodule AshPlatformWeb.Live.LaunchGateHook do
  @moduledoc """
  Keeps product LiveViews closed while the launch gate is closed, including
  mounts that reach the socket without a fresh request: reconnects and live
  navigation from a page loaded before the gate closed.
  """

  use AshPlatformWeb, :verified_routes

  alias AshPlatformWeb.Plugs.LaunchGate

  def on_mount(:default, _params, _session, socket),
    do: gate(LaunchGate.app_surfaces_enabled?(), socket)

  defp gate(true, socket), do: {:cont, socket}
  defp gate(false, socket), do: {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/")}
end
