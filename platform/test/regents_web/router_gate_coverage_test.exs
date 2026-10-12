defmodule RegentsWeb.RouterGateCoverageTest do
  @moduledoc """
  Walks the router's own route table so a route added later cannot quietly
  escape the launch gate: a new pipeline without the gate, a route with no
  pipeline at all, or a product LiveView placed outside the gated live session
  all fail here.
  """

  use RegentsWeb.ConnCase, async: false

  alias RegentsWeb.Live.LaunchGateHook

  setup do
    Application.put_env(:regents, :app_surfaces, false)
    on_exit(fn -> Application.put_env(:regents, :app_surfaces, true) end)
    :ok
  end

  test "[U2] only the public operational routes, marketing and reading pages and sign-out stay open" do
    still_open =
      for route <- routes(),
          conn = request(route),
          conn.status != 503,
          do: {route.verb, route.path}

    assert still_open == [
             {:get, "/healthz"},
             {:get, "/developers"},
             {:get, "/openapi.json"},
             {:get, "/sitemap.xml"},
             {:get, "/robots.txt"},
             {:get, "/capabilities"},
             {:get, "/agents.md"},
             {:get, "/skill.md"},
             {:get, "/llms.txt"},
             {:get, "/.well-known/security.txt"},
             {:get, "/paper-pro-daily/pictures/:id"},
             {:get, "/articles/covers/:slug"},
             {:get, "/docs"},
             {:get, "/about"},
             {:get, "/contact"},
             {:get, "/"},
             {:get, "/paper-pro-daily"},
             {:get, "/literature"},
             {:get, "/privacy"},
             {:get, "/terms"},
             {:delete, "/auth/privy/session"},
             {:get, "/articles"},
             {:get, "/articles/:slug"},
             {:get, "/admin/articles"},
             {:get, "/admin/errors"},
             {:get, "/admin/errors/:id"},
             {:get, "/admin/errors/:id/:occurrence_id"}
           ]

    # Sean publishes articles and Credits admins read the saved errors while the
    # gate is closed; anyone else is told neither page exists.
    assert request(%{verb: :get, path: "/admin/articles"}).status == 404
    assert request(%{verb: :get, path: "/admin/errors"}).status == 404
  end

  test "[U2] every product LiveView mounts through the gate" do
    ungated =
      for route <- routes(),
          live_view = route.metadata[:phoenix_live_view],
          route.path not in ["/", "/paper-pro-daily", "/literature"],
          # The saved errors are Credits admins' own pages (RegentsWeb.ErrorsAdmin).
          not String.starts_with?(route.path, "/admin/errors"),
          not mounts_through_gate?(live_view),
          do: route.path

    assert ungated == []
  end

  # The development workshop has an independent loopback gate, exercised by
  # ShowcaseTest for both HTTP and connected mounts. It is absent in production.
  defp routes do
    RegentsWeb.Router
    |> Phoenix.Router.routes()
    |> Enum.reject(fn route ->
      method = route.verb |> Atom.to_string() |> String.upcase()

      info =
        Phoenix.Router.route_info(
          RegentsWeb.Router,
          method,
          concrete_path(route.path),
          "localhost"
        )

      :local_showcase in info.pipe_through
    end)
  end

  defp request(route) do
    Phoenix.ConnTest.dispatch(build_conn(), @endpoint, route.verb, concrete_path(route.path), %{})
  rescue
    # An open reading page asked for an article that does not exist answers
    # "not found", which still counts as open.
    RegentsWeb.NotFoundError -> %{status: 404}
  end

  # Placeholders stand in for path parameters; a closed gate answers before any
  # controller or LiveView reads them.
  defp concrete_path(path) do
    String.replace(path, ~r{/[:*][^/]+}, "/gate-coverage")
  end

  defp mounts_through_gate?({_module, _action, _opts, %{extra: %{on_mount: hooks}}}) do
    Enum.any?(hooks, &(&1.id == {LaunchGateHook, :default}))
  end

  defp mounts_through_gate?(_live_view), do: false
end
