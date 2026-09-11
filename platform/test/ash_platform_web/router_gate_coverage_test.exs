defmodule AshPlatformWeb.RouterGateCoverageTest do
  @moduledoc """
  Walks the router's own route table so a route added later cannot quietly
  escape the launch gate: a new pipeline without the gate, a route with no
  pipeline at all, or a product LiveView placed outside the gated live session
  all fail here.
  """

  use AshPlatformWeb.ConnCase, async: false

  alias AshPlatformWeb.Live.LaunchGateHook

  setup do
    Application.put_env(:ash_platform, :app_surfaces, false)
    on_exit(fn -> Application.put_env(:ash_platform, :app_surfaces, true) end)
    :ok
  end

  test "[U2] only the public operational routes, marketing page and sign-out stay open" do
    still_open =
      for route <- routes(),
          conn = request(route),
          conn.status != 503,
          do: {route.verb, route.path}

    assert still_open == [
             {:get, "/healthz"},
             {:get, "/metrics"},
             {:get, "/"},
             {:get, "/privacy"},
             {:get, "/terms"},
             {:get, "/blog"},
             {:get, "/blog/:slug"},
             {:delete, "/auth/privy/session"}
           ]
  end

  test "[U2] every product LiveView mounts through the gate" do
    ungated =
      for route <- routes(),
          live_view = route.metadata[:phoenix_live_view],
          route.path != "/",
          not mounts_through_gate?(live_view),
          do: route.path

    assert ungated == []
  end

  # The development workshop has an independent loopback gate, exercised by
  # ShowcaseTest for both HTTP and connected mounts. It is absent in production.
  defp routes do
    AshPlatformWeb.Router
    |> Phoenix.Router.routes()
    |> Enum.reject(fn route ->
      method = route.verb |> Atom.to_string() |> String.upcase()

      info =
        Phoenix.Router.route_info(
          AshPlatformWeb.Router,
          method,
          concrete_path(route.path),
          "localhost"
        )

      :local_showcase in info.pipe_through
    end)
  end

  defp request(route) do
    Phoenix.ConnTest.dispatch(build_conn(), @endpoint, route.verb, concrete_path(route.path), %{})
  end

  # Placeholders stand in for path parameters; the gate answers before any
  # controller or LiveView reads them.
  defp concrete_path(path) do
    String.replace(path, ~r{/[:*][^/]+}, "/gate-coverage")
  end

  defp mounts_through_gate?({_module, _action, _opts, %{extra: %{on_mount: hooks}}}) do
    Enum.any?(hooks, &(&1.id == {LaunchGateHook, :default}))
  end

  defp mounts_through_gate?(_live_view), do: false
end
