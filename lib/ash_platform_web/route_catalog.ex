defmodule AshPlatformWeb.RouteCatalog do
  @moduledoc "Canonical behavior metadata for the founder-approved route allowlist."

  alias AshPlatformWeb.NotFoundError

  alias __MODULE__.{
    AppTarget,
    Entry,
    RouteTarget,
    SidebarModel,
    Spec,
    TreeTarget,
    ViewerProfileTarget
  }

  @identifier ~r/\A[a-zA-Z0-9][a-zA-Z0-9._:-]{0,127}\z/
  @slug ~r/\A[a-z0-9][a-z0-9-]{0,62}\z/

  @trees Enum.map(AshPlatform.Techtree.SeedTrees.all(), &{&1.slug, &1.name})
  @tree_names Map.new(@trees)

  @entries [
    %Entry{
      path_pattern: "/",
      live_action: :home,
      parameter_schema: %{},
      reserved_values: %{},
      route_spec_id: :home
    },
    %Entry{
      path_pattern: "/app",
      live_action: :app,
      parameter_schema: %{},
      reserved_values: %{},
      route_spec_id: :app
    },
    %Entry{
      path_pattern: "/settings",
      live_action: :settings,
      parameter_schema: %{},
      reserved_values: %{},
      route_spec_id: :settings
    },
    %Entry{
      path_pattern: "/formation",
      live_action: :formation,
      parameter_schema: %{},
      reserved_values: %{},
      route_spec_id: :formation
    },
    %Entry{
      path_pattern: "/regents/:slug",
      live_action: :regent_profile,
      parameter_schema: %{slug: :slug},
      reserved_values: %{},
      route_spec_id: :regent_profile
    },
    %Entry{
      path_pattern: "/techtree",
      live_action: :techtree,
      parameter_schema: %{},
      reserved_values: %{},
      route_spec_id: :techtree
    },
    %Entry{
      path_pattern: "/techtree/nodes/:node_id",
      live_action: :techtree_node,
      parameter_schema: %{node_id: :identifier},
      reserved_values: %{},
      route_spec_id: :techtree_node
    },
    %Entry{
      path_pattern: "/techtree/:tree_slug",
      live_action: :techtree_tree,
      parameter_schema: %{tree_slug: :tree_slug},
      reserved_values: %{tree_slug: ["nodes"]},
      route_spec_id: :techtree_tree
    },
    %Entry{
      path_pattern: "/autolaunch",
      live_action: :autolaunch,
      parameter_schema: %{},
      reserved_values: %{},
      route_spec_id: :autolaunch
    },
    %Entry{
      path_pattern: "/autolaunch/auctions",
      live_action: :autolaunch_auctions,
      parameter_schema: %{},
      reserved_values: %{},
      route_spec_id: :autolaunch_auctions
    },
    %Entry{
      path_pattern: "/autolaunch/auctions/:auction_id",
      live_action: :autolaunch_auction,
      parameter_schema: %{auction_id: :identifier},
      reserved_values: %{},
      route_spec_id: :autolaunch_auction
    },
    %Entry{
      path_pattern: "/autolaunch/tokens",
      live_action: :autolaunch_tokens,
      parameter_schema: %{},
      reserved_values: %{},
      route_spec_id: :autolaunch_tokens
    },
    %Entry{
      path_pattern: "/autolaunch/tokens/:token_id",
      live_action: :autolaunch_token,
      parameter_schema: %{token_id: :identifier},
      reserved_values: %{},
      route_spec_id: :autolaunch_token
    },
    %Entry{
      path_pattern: "/autolaunch/launches",
      live_action: :autolaunch_launches,
      parameter_schema: %{},
      reserved_values: %{},
      route_spec_id: :autolaunch_launches
    },
    %Entry{
      path_pattern: "/autolaunch/launches/:id",
      live_action: :autolaunch_launch,
      parameter_schema: %{id: :identifier},
      reserved_values: %{},
      route_spec_id: :autolaunch_launch
    },
    %Entry{
      path_pattern: "/autolaunch/subjects",
      live_action: :autolaunch_subjects,
      parameter_schema: %{},
      reserved_values: %{},
      route_spec_id: :autolaunch_subjects
    },
    %Entry{
      path_pattern: "/autolaunch/subjects/:id",
      live_action: :autolaunch_subject,
      parameter_schema: %{id: :identifier},
      reserved_values: %{},
      route_spec_id: :autolaunch_subject
    },
    %Entry{
      path_pattern: "/autolaunch/holdings",
      live_action: :autolaunch_holdings,
      parameter_schema: %{},
      reserved_values: %{},
      route_spec_id: :autolaunch_holdings
    },
    %Entry{
      path_pattern: "/autolaunch/create",
      live_action: :autolaunch_create,
      parameter_schema: %{},
      reserved_values: %{},
      route_spec_id: :autolaunch_create
    },
    %Entry{
      path_pattern: "/stake",
      live_action: :stake,
      parameter_schema: %{},
      reserved_values: %{},
      route_spec_id: :stake
    },
    %Entry{
      path_pattern: "/redeem",
      live_action: :redeem,
      parameter_schema: %{},
      reserved_values: %{},
      route_spec_id: :redeem
    }
  ]

  @app_targets [
    %AppTarget{app_id: :formation, label: "Nous Portal", path: "/formation"},
    %AppTarget{app_id: :autolaunch, label: "Autolaunch", path: "/autolaunch"},
    %AppTarget{app_id: :techtree, label: "Techtree", path: "/techtree"},
    %AppTarget{app_id: :regent_ops, label: "Regents Labs", path: "/app"}
  ]

  @specs %{
    home: {:home, nil, nil, "Regent", "/", [], :none, :home, :landing, %{}},
    app:
      {:app, :regent_ops, "Regents Labs", "Overview", "/app",
       [:wallet_status, :network_status, :profile_actions], :none, :regents_labs, :overview, %{}},
    settings:
      {:settings, :regent_ops, "Regents Labs", "Settings", "/app", [:profile_actions], :none,
       :regents_labs, :detail, %{}},
    formation:
      {:formation, :formation, "Nous Portal", "Formation", "/formation", [:profile_actions],
       :none, :formation, :lifecycle, %{}},
    regent_profile:
      {:regent_profile, :regent_ops, "Regents Labs", "Regent Profile", "/app",
       [:wallet_status, :network_status, :profile_actions], :none, :regent_record, :detail, %{}},
    techtree:
      {:techtree, :techtree, "Techtree", "Techtree", "/techtree",
       [:view_switcher, :profile_actions], :none, :techtree_overview, :overview, %{}},
    techtree_node:
      {:techtree_node, :techtree, "Techtree", "Node", "/techtree",
       [:view_switcher, :profile_actions], :none, :techtree_node, :detail, %{}},
    techtree_tree:
      {:techtree_tree, :techtree, "Techtree", nil, "/techtree",
       [:view_switcher, :profile_actions], :none, :techtree_tree, :tree,
       %{presentation: %{default: :map, values: [:map, :list]}}},
    autolaunch:
      {:autolaunch, :autolaunch, "Autolaunch", "Autolaunch", "/autolaunch",
       [:search, :filters, :profile_actions], :autolaunch, :autolaunch, :overview, %{}},
    autolaunch_auctions:
      {:autolaunch_auctions, :autolaunch, "Autolaunch", "Auctions", "/autolaunch",
       [:search, :filters, :profile_actions], :autolaunch, :autolaunch, :collection, %{}},
    autolaunch_auction:
      {:autolaunch_auction, :autolaunch, "Autolaunch", "Auction", "/autolaunch",
       [:search, :filters, :wallet_status, :network_status, :profile_actions], :autolaunch,
       :autolaunch, :detail, %{}},
    autolaunch_tokens:
      {:autolaunch_tokens, :autolaunch, "Autolaunch", "Tokens", "/autolaunch",
       [:search, :filters, :profile_actions], :autolaunch, :autolaunch, :collection, %{}},
    autolaunch_token:
      {:autolaunch_token, :autolaunch, "Autolaunch", "Token", "/autolaunch",
       [:search, :filters, :wallet_status, :network_status, :profile_actions], :autolaunch,
       :autolaunch, :detail, %{}},
    autolaunch_launches:
      {:autolaunch_launches, :autolaunch, "Autolaunch", "Launches", "/autolaunch",
       [:search, :filters, :profile_actions], :autolaunch, :autolaunch, :collection, %{}},
    autolaunch_launch:
      {:autolaunch_launch, :autolaunch, "Autolaunch", "Launch", "/autolaunch",
       [:search, :filters, :profile_actions], :autolaunch, :autolaunch, :detail, %{}},
    autolaunch_subjects:
      {:autolaunch_subjects, :autolaunch, "Autolaunch", "Subjects", "/autolaunch",
       [:search, :filters, :profile_actions], :autolaunch, :autolaunch, :collection, %{}},
    autolaunch_subject:
      {:autolaunch_subject, :autolaunch, "Autolaunch", "Subject", "/autolaunch",
       [:search, :filters, :profile_actions], :autolaunch, :autolaunch, :detail, %{}},
    autolaunch_holdings:
      {:autolaunch_holdings, :autolaunch, "Autolaunch", "Holdings", "/autolaunch",
       [:wallet_status, :profile_actions], :autolaunch, :autolaunch, :collection, %{}},
    autolaunch_create:
      {:autolaunch_create, :autolaunch, "Autolaunch", "Create", "/autolaunch",
       [:search, :filters, :profile_actions], :autolaunch, :autolaunch, :workflow, %{}},
    stake:
      {:stake, :regent_ops, "Regents Labs", "Stake", "/app",
       [:wallet_status, :network_status, :profile_actions], :none, :regents_labs, :workflow, %{}},
    redeem:
      {:redeem, :regent_ops, "Regents Labs", "Redeem", "/app",
       [:wallet_status, :network_status, :profile_actions], :none, :regents_labs, :workflow, %{}}
  }

  def entries, do: @entries

  def tree_roots, do: @trees
  def app_targets, do: @app_targets

  def fetch!(action, params \\ %{}) do
    entry = Enum.find(@entries, &(&1.live_action == action)) || raise(NotFoundError)
    validate_params!(entry, params)
    build_spec(entry.route_spec_id, params)
  end

  def design_handoff do
    json =
      %{"schema_version" => 1, "routes" => Enum.map(@entries, &handoff_route/1)}
      |> ordered_json_value()
      |> Jason.encode!()

    %{json: json, digest: Base.encode16(:crypto.hash(:sha256, json), case: :lower)}
  end

  defp validate_params!(%Entry{parameter_schema: schema, reserved_values: reserved}, params) do
    valid? =
      Enum.all?(schema, fn {key, type} ->
        value = Map.get(params, Atom.to_string(key))
        valid_parameter?(type, value) and value not in Map.get(reserved, key, [])
      end)

    if valid?, do: :ok, else: raise(NotFoundError)
  end

  defp valid_parameter?(:slug, value), do: is_binary(value) and Regex.match?(@slug, value)

  defp valid_parameter?(:identifier, value),
    do: is_binary(value) and Regex.match?(@identifier, value)

  defp valid_parameter?(:tree_slug, value),
    do: is_binary(value) and is_map_key(@tree_names, value)

  defp build_spec(action, params) do
    {route_id, app_id, app_label, page_label, root, controls, search, background, transition,
     local_state} = Map.fetch!(@specs, action)

    %Spec{
      route_id: route_id,
      destination: destination(action, params),
      app_id: app_id,
      app_display_label: app_label,
      page_display_label: page_label || Map.fetch!(@tree_names, params["tree_slug"]),
      canonical_root: root,
      sidebar_model: sidebar_model(app_id),
      header_controls: controls,
      search_kind: search,
      background_slot: background,
      content_transition_kind: transition,
      scroll_policy: :top,
      local_state: local_state
    }
  end

  defp sidebar_model(nil), do: %SidebarModel{id: :public, targets: []}

  defp sidebar_model(:formation) do
    %SidebarModel{
      id: :formation,
      targets: []
    }
  end

  defp sidebar_model(:techtree) do
    tree_targets =
      Enum.map(@trees, fn {slug, label} ->
        %TreeTarget{
          tree_slug: slug,
          label: label,
          path: "/techtree/#{slug}",
          presentations: [:map, :list]
        }
      end)

    %SidebarModel{
      id: :techtree,
      targets: tree_targets
    }
  end

  defp sidebar_model(:autolaunch) do
    %SidebarModel{
      id: :autolaunch,
      targets: [
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
          route_id: :autolaunch_holdings,
          label: "Holdings",
          path: "/autolaunch/holdings"
        },
        %RouteTarget{
          route_id: :autolaunch_create,
          label: "Create",
          path: "/autolaunch/create"
        }
      ]
    }
  end

  defp sidebar_model(:regent_ops) do
    %SidebarModel{
      id: :regent_ops,
      targets: [
        %RouteTarget{route_id: :app, label: "Overview", path: "/app"},
        %RouteTarget{route_id: :stake, label: "Stake", path: "/stake"},
        %RouteTarget{route_id: :redeem, label: "Redeem", path: "/redeem"},
        %ViewerProfileTarget{label: "Profile"}
      ]
    }
  end

  defp handoff_route(entry) do
    spec = fetch!(entry.live_action, handoff_params(entry.live_action))

    %{
      "app_display_label" => spec.app_display_label,
      "app_id" => spec.app_id,
      "background_slot" => spec.background_slot,
      "canonical_root" => spec.canonical_root,
      "content_transition_kind" => spec.content_transition_kind,
      "destination" => spec.destination,
      "header_controls" => spec.header_controls,
      "live_action" => entry.live_action,
      "local_state" => spec.local_state,
      "page_display_label" => spec.page_display_label,
      "parameter_schema" => entry.parameter_schema,
      "path_pattern" => entry.path_pattern,
      "reserved_values" => entry.reserved_values,
      "route_id" => spec.route_id,
      "scroll_policy" => spec.scroll_policy,
      "search_kind" => spec.search_kind,
      "sidebar_model" => sidebar_handoff(spec.sidebar_model)
    }
  end

  defp sidebar_handoff(sidebar) do
    %{"id" => sidebar.id, "targets" => Enum.map(sidebar.targets, &sidebar_target_handoff/1)}
  end

  defp sidebar_target_handoff(%RouteTarget{} = target) do
    %{
      "type" => "route",
      "route_id" => target.route_id,
      "label" => target.label,
      "destination" => target.path
    }
  end

  defp sidebar_target_handoff(%TreeTarget{} = target) do
    %{
      "type" => "tree",
      "label" => target.label,
      "destination" => target.path,
      "tree" => target.tree_slug,
      "presentations" =>
        Enum.map(target.presentations, fn presentation ->
          %{
            "type" => "tree_presentation",
            "destination" => target.path,
            "tree" => target.tree_slug,
            "presentation" => presentation
          }
        end)
    }
  end

  defp sidebar_target_handoff(%ViewerProfileTarget{} = target) do
    %{
      "type" => "viewer_profile",
      "label" => target.label,
      "destination" => "/regents/:viewer_slug"
    }
  end

  defp handoff_params(:regent_profile), do: %{"slug" => "regent"}
  defp handoff_params(:techtree_node), do: %{"node_id" => "node"}

  defp handoff_params(:techtree_tree),
    do: %{"tree_slug" => "genebench-pro-reference-lab"}

  defp handoff_params(:autolaunch_auction), do: %{"auction_id" => "auction"}
  defp handoff_params(:autolaunch_token), do: %{"token_id" => "token"}
  defp handoff_params(:autolaunch_launch), do: %{"id" => "launch"}
  defp handoff_params(:autolaunch_subject), do: %{"id" => "subject"}
  defp handoff_params(_), do: %{}

  defp destination(:regent_profile, %{"slug" => slug}), do: "/regents/#{slug}"
  defp destination(:techtree_node, %{"node_id" => node_id}), do: "/techtree/nodes/#{node_id}"
  defp destination(:techtree_tree, %{"tree_slug" => slug}), do: "/techtree/#{slug}"

  defp destination(:autolaunch_auction, %{"auction_id" => auction_id}),
    do: "/autolaunch/auctions/#{auction_id}"

  defp destination(:autolaunch_token, %{"token_id" => token_id}),
    do: "/autolaunch/tokens/#{token_id}"

  defp destination(:autolaunch_launch, %{"id" => id}),
    do: "/autolaunch/launches/#{id}"

  defp destination(:autolaunch_subject, %{"id" => id}),
    do: "/autolaunch/subjects/#{id}"

  defp destination(action, _params) do
    @entries
    |> Enum.find(&(&1.live_action == action))
    |> Map.fetch!(:path_pattern)
  end

  defp ordered_json_value(value) when is_map(value) do
    value
    |> Enum.map(fn {key, nested_value} ->
      {to_string(key), ordered_json_value(nested_value)}
    end)
    |> Enum.sort_by(&elem(&1, 0))
    |> Jason.OrderedObject.new()
  end

  defp ordered_json_value(value) when is_list(value), do: Enum.map(value, &ordered_json_value/1)
  defp ordered_json_value(value), do: value
end
