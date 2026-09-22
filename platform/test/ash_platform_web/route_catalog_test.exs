defmodule AshPlatformWeb.RouteCatalogTest do
  use ExUnit.Case, async: true

  alias AshPlatformWeb.{NotFoundError, RouteCatalog, Router}

  alias AshPlatformWeb.RouteCatalog.{
    RouteTarget,
    SidebarHeading,
    ViewerProfileTarget
  }

  @paths [
    "/",
    "/app",
    "/account",
    "/formation",
    "/regents/:slug",
    "/stake",
    "/redeem",
    "/autolaunch",
    "/techtree",
    "/patchbay"
  ]

  test "contains exactly the founder-approved pages" do
    assert Enum.map(RouteCatalog.entries(), & &1.path_pattern) == @paths
  end

  test "runtime GET router and catalog have identical paths, actions, order, and precedence" do
    runtime_routes =
      Router
      |> Phoenix.Router.routes()
      |> Enum.filter(&(&1.verb == :get and &1.plug == Phoenix.LiveView.Plug))
      # Compile-disabled in production; the workshop has its own loopback gate.
      |> Enum.reject(fn route ->
        :local_showcase in Phoenix.Router.route_info(Router, "GET", route.path, "localhost").pipe_through
      end)
      |> Enum.map(&{&1.path, &1.plug_opts})

    catalog_routes = Enum.map(RouteCatalog.entries(), &{&1.path_pattern, &1.live_action})

    assert runtime_routes == catalog_routes
  end

  test "every catalog entry builds the route spec it declares, including /app" do
    assert Enum.all?(RouteCatalog.entries(), fn entry ->
             spec = RouteCatalog.fetch!(entry.live_action, sample_params(entry.live_action))
             spec.route_id == entry.route_spec_id
           end)

    app_entry = Enum.find(RouteCatalog.entries(), &(&1.path_pattern == "/app"))
    assert app_entry.route_spec_id == :app
    assert RouteCatalog.fetch!(:app).route_id == :app
  end

  test "account is the canonical Regents Labs detail route" do
    account = RouteCatalog.fetch!(:account)

    assert account.route_id == :account
    assert account.destination == "/account"
    assert account.app_id == :regent_ops
    assert account.app_display_label == "Regents Labs"
    assert account.page_display_label == "Account"
    assert account.canonical_root == "/app"
    assert account.header_controls == [:profile_actions]
    assert account.background_slot == :regents_labs
    assert account.content_transition_kind == :detail
    assert account.local_state == %{}
  end

  test "Formation keeps its route truth without local panel targets or state" do
    formation = RouteCatalog.fetch!(:formation)

    assert formation.route_id == :formation
    assert formation.destination == "/formation"
    assert formation.app_id == :formation
    assert formation.app_display_label == "Nous Portal"
    assert formation.page_display_label == "Formation"
    assert formation.canonical_root == "/formation"
    assert formation.background_slot == :formation
    assert formation.header_controls == [:profile_actions]
    assert formation.content_transition_kind == :lifecycle
    assert formation.scroll_policy == :top
    assert formation.sidebar_model.targets == []
    assert formation.local_state == %{}

    assert RouteCatalog.fetch!(:app).sidebar_model.targets == [
             %RouteTarget{route_id: :app, label: "Overview", path: "/app"},
             %RouteTarget{route_id: :stake, label: "Stake", path: "/stake"},
             %RouteTarget{route_id: :redeem, label: "Redeem", path: "/redeem"},
             %ViewerProfileTarget{label: "Profile"},
             %SidebarHeading{label: "Products"},
             %RouteTarget{route_id: :autolaunch, label: "Autolaunch", path: "/autolaunch"},
             %RouteTarget{route_id: :techtree, label: "Techtree", path: "/techtree"},
             %RouteTarget{route_id: :patchbay, label: "Patchbay", path: "/patchbay"}
           ]
  end

  test "rejects empty and malformed dynamic identifiers before content loading" do
    for {action, params} <- [
          {:regent_profile, %{"slug" => ""}},
          {:regent_profile, %{"slug" => "not valid"}}
        ] do
      assert_raise NotFoundError, fn -> RouteCatalog.fetch!(action, params) end
    end
  end

  test "header controls use the closed contract" do
    allowed_controls =
      MapSet.new([
        :search,
        :filters,
        :view_switcher,
        :wallet_status,
        :network_status,
        :profile_actions
      ])

    assert Enum.all?(RouteCatalog.entries(), fn entry ->
             spec = RouteCatalog.fetch!(entry.live_action, sample_params(entry.live_action))
             MapSet.subset?(MapSet.new(spec.header_controls), allowed_controls)
           end)
  end

  test "every route starts at the top" do
    assert Enum.all?(RouteCatalog.entries(), fn entry ->
             RouteCatalog.fetch!(entry.live_action, sample_params(entry.live_action)).scroll_policy ==
               :top
           end)
  end

  test "Design handoff JSON and digest are deterministic" do
    first = RouteCatalog.design_handoff()
    second = RouteCatalog.design_handoff()

    assert first == second
    assert {:ok, decoded} = Jason.decode(first.json)
    assert length(decoded["routes"]) == 10
    assert decoded["schema_version"] == 1
    assert first.digest == Base.encode16(:crypto.hash(:sha256, first.json), case: :lower)

    targets =
      decoded["routes"]
      |> Enum.flat_map(& &1["sidebar_model"]["targets"])

    assert Enum.all?(targets, &is_binary(&1["type"]))

    assert Enum.all?(targets, fn
             %{"type" => "route", "destination" => path, "route_id" => route_id}
             when is_binary(path) and is_binary(route_id) ->
               true

             %{"type" => "viewer_profile", "destination" => "/regents/:viewer_slug"} ->
               true

             %{"type" => "heading", "label" => label} when is_binary(label) ->
               true

             _target ->
               false
           end)

    assert %{"sidebar_model" => %{"targets" => []}} =
             Enum.find(decoded["routes"], &(&1["route_id"] == "formation"))
  end

  defp sample_params(:regent_profile), do: %{"slug" => "regent"}
  defp sample_params(_), do: %{}
end
