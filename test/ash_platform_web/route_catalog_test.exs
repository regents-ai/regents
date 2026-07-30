defmodule AshPlatformWeb.RouteCatalogTest do
  use ExUnit.Case, async: true

  alias AshPlatformWeb.{NotFoundError, RouteCatalog, Router}

  alias AshPlatformWeb.RouteCatalog.{
    FormationPanelTarget,
    RouteTarget,
    TreeTarget,
    ViewerProfileTarget
  }

  @paths [
    "/",
    "/app",
    "/settings",
    "/formation",
    "/regents/:slug",
    "/techtree",
    "/techtree/nodes/:node_id",
    "/techtree/:tree_slug",
    "/autolaunch",
    "/autolaunch/auctions",
    "/autolaunch/auctions/:auction_id",
    "/autolaunch/tokens",
    "/autolaunch/tokens/:token_id",
    "/autolaunch/launches",
    "/autolaunch/launches/:id",
    "/autolaunch/subjects",
    "/autolaunch/subjects/:id",
    "/autolaunch/create",
    "/stake",
    "/redeem"
  ]

  test "contains exactly the founder-approved pages" do
    assert Enum.map(RouteCatalog.entries(), & &1.path_pattern) == @paths
  end

  test "runtime GET router and catalog have identical paths, actions, order, and precedence" do
    runtime_routes =
      Router
      |> Phoenix.Router.routes()
      |> Enum.filter(&(&1.verb == :get and &1.plug == Phoenix.LiveView.Plug))
      |> Enum.map(&{&1.path, &1.plug_opts})

    catalog_routes = Enum.map(RouteCatalog.entries(), &{&1.path_pattern, &1.live_action})

    assert runtime_routes == catalog_routes

    assert Enum.find_index(runtime_routes, &match?({"/techtree/nodes/:node_id", _}, &1)) <
             Enum.find_index(runtime_routes, &match?({"/techtree/:tree_slug", _}, &1))
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

  test "settings is the canonical Regents Labs detail route" do
    settings = RouteCatalog.fetch!(:settings)

    assert settings.route_id == :settings
    assert settings.destination == "/settings"
    assert settings.app_id == :regent_ops
    assert settings.app_display_label == "Regents Labs"
    assert settings.page_display_label == "Settings"
    assert settings.canonical_root == "/app"
    assert settings.header_controls == [:profile_actions]
    assert settings.search_kind == :none
    assert settings.background_slot == :regents_labs
    assert settings.content_transition_kind == :detail
    assert settings.local_state == %{}
  end

  test "accepts only the five named tree slugs and reserves nodes" do
    assert Enum.count(RouteCatalog.tree_roots()) == 5

    assert_raise NotFoundError, fn ->
      RouteCatalog.fetch!(:techtree_tree, %{"tree_slug" => "nodes"})
    end

    assert_raise NotFoundError, fn ->
      RouteCatalog.fetch!(:techtree_tree, %{"tree_slug" => "other"})
    end
  end

  test "sidebars exactly match founder order and target behavior" do
    formation = RouteCatalog.fetch!(:formation)

    assert formation.sidebar_model.targets == [
             %FormationPanelTarget{panel: :overview, label: "Overview"},
             %FormationPanelTarget{panel: :cloud, label: "Cloud"},
             %FormationPanelTarget{panel: :hermes_skills, label: "Hermes Skills"},
             %FormationPanelTarget{panel: :billing, label: "Billing"}
           ]

    assert formation.local_state == %{
             panel: %{default: :overview, values: [:overview, :cloud, :hermes_skills, :billing]}
           }

    assert RouteCatalog.fetch!(:autolaunch).sidebar_model.targets == [
             %RouteTarget{
               route_id: :autolaunch_auctions,
               label: "Auctions",
               path: "/autolaunch/auctions"
             },
             %RouteTarget{
               route_id: :autolaunch_tokens,
               label: "Tokens",
               path: "/autolaunch/tokens"
             },
             %RouteTarget{
               route_id: :autolaunch_launches,
               label: "Launches",
               path: "/autolaunch/launches"
             },
             %RouteTarget{
               route_id: :autolaunch_subjects,
               label: "Subjects",
               path: "/autolaunch/subjects"
             },
             %RouteTarget{
               route_id: :autolaunch_create,
               label: "Create",
               path: "/autolaunch/create"
             }
           ]

    assert RouteCatalog.fetch!(:app).sidebar_model.targets == [
             %RouteTarget{route_id: :app, label: "Overview", path: "/app"},
             %RouteTarget{route_id: :stake, label: "Stake", path: "/stake"},
             %RouteTarget{route_id: :redeem, label: "Redeem", path: "/redeem"},
             %ViewerProfileTarget{label: "Profile"}
           ]

    assert RouteCatalog.fetch!(:techtree).sidebar_model.targets ==
             Enum.map(RouteCatalog.tree_roots(), fn {slug, label} ->
               %TreeTarget{
                 tree_slug: slug,
                 label: label,
                 path: "/techtree/#{slug}",
                 presentations: [:map, :list]
               }
             end)
  end

  test "rejects empty and malformed dynamic identifiers before content loading" do
    for {action, params} <- [
          {:regent_profile, %{"slug" => ""}},
          {:regent_profile, %{"slug" => "not valid"}},
          {:techtree_node, %{"node_id" => "../node"}},
          {:autolaunch_auction, %{"auction_id" => String.duplicate("a", 129)}},
          {:autolaunch_token, %{}},
          {:autolaunch_launch, %{"id" => "launch/slash"}},
          {:autolaunch_subject, %{"id" => "../subject"}}
        ] do
      assert_raise NotFoundError, fn -> RouteCatalog.fetch!(action, params) end
    end
  end

  test "search is admitted only for Techtree and Autolaunch" do
    searchable =
      RouteCatalog.entries()
      |> Enum.map(&RouteCatalog.fetch!(&1.live_action, sample_params(&1.live_action)))
      |> Enum.reject(&(&1.search_kind == :none))

    assert Enum.all?(searchable, &(&1.app_id in [:techtree, :autolaunch]))
  end

  test "app selector roots and header controls use the closed contract" do
    assert Enum.map(RouteCatalog.app_targets(), & &1.path) == [
             "/formation",
             "/autolaunch",
             "/techtree",
             "/app"
           ]

    allowed_controls =
      MapSet.new([
        :provisioning_status,
        :runtime_action,
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

  test "same-tree presentation is local and every route starts at the top" do
    tree =
      RouteCatalog.fetch!(:techtree_tree, %{
        "tree_slug" => "genebench-pro-reference-lab"
      })

    assert tree.local_state == %{presentation: %{default: :map, values: [:map, :list]}}
    assert tree.scroll_policy == :top

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
    assert length(decoded["routes"]) == 20
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

             %{"type" => "formation_panel", "destination" => "/formation", "panel" => panel}
             when is_binary(panel) ->
               true

             %{
               "type" => "tree",
               "destination" => path,
               "tree" => tree,
               "presentations" => [
                 %{"type" => "tree_presentation", "presentation" => "map"},
                 %{"type" => "tree_presentation", "presentation" => "list"}
               ]
             }
             when is_binary(path) and is_binary(tree) ->
               true

             %{"type" => "viewer_profile", "destination" => "/regents/:viewer_slug"} ->
               true

             _target ->
               false
           end)
  end

  defp sample_params(:techtree_tree), do: %{"tree_slug" => "genebench-pro-reference-lab"}
  defp sample_params(:regent_profile), do: %{"slug" => "regent"}
  defp sample_params(:techtree_node), do: %{"node_id" => "node"}
  defp sample_params(:autolaunch_auction), do: %{"auction_id" => "auction"}
  defp sample_params(:autolaunch_token), do: %{"token_id" => "token"}
  defp sample_params(:autolaunch_launch), do: %{"id" => "launch"}
  defp sample_params(:autolaunch_subject), do: %{"id" => "subject"}
  defp sample_params(_), do: %{}
end
