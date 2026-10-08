defmodule RegentsWeb.RouteCatalog do
  @moduledoc "Canonical behavior metadata for the founder-approved route allowlist."

  alias RegentsWeb.NotFoundError

  alias __MODULE__.{
    Entry,
    PageTarget,
    RouteTarget,
    SidebarHeading,
    SidebarModel,
    Spec,
    ViewerProfileTarget
  }

  @slug ~r/\A[a-z0-9][a-z0-9-]{0,62}\z/

  @entries [
    %Entry{
      path_pattern: "/",
      live_action: :home,
      parameter_schema: %{},
      reserved_values: %{},
      route_spec_id: :home
    },
    %Entry{
      path_pattern: "/paper-pro-daily",
      live_action: :paper_pro_daily,
      parameter_schema: %{},
      reserved_values: %{},
      route_spec_id: :paper_pro_daily
    },
    %Entry{
      path_pattern: "/app",
      live_action: :app,
      parameter_schema: %{},
      reserved_values: %{},
      route_spec_id: :app
    },
    %Entry{
      path_pattern: "/account",
      live_action: :account,
      parameter_schema: %{},
      reserved_values: %{},
      route_spec_id: :account
    },
    %Entry{
      path_pattern: "/account/credits",
      live_action: :account_credits,
      parameter_schema: %{},
      reserved_values: %{},
      route_spec_id: :account_credits
    },
    %Entry{
      path_pattern: "/account/points",
      live_action: :account_points,
      parameter_schema: %{},
      reserved_values: %{},
      route_spec_id: :account_points
    },
    %Entry{
      path_pattern: "/regents/:slug",
      live_action: :regent_profile,
      parameter_schema: %{slug: :slug},
      reserved_values: %{},
      route_spec_id: :regent_profile
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
    },
    %Entry{
      path_pattern: "/redeem/gallery",
      live_action: :redeem_gallery,
      parameter_schema: %{},
      reserved_values: %{},
      route_spec_id: :redeem_gallery
    },
    %Entry{
      path_pattern: "/autolaunch",
      live_action: :autolaunch,
      parameter_schema: %{},
      reserved_values: %{},
      route_spec_id: :autolaunch
    },
    %Entry{
      path_pattern: "/techtree",
      live_action: :techtree,
      parameter_schema: %{},
      reserved_values: %{},
      route_spec_id: :techtree
    },
    %Entry{
      path_pattern: "/patchbay",
      live_action: :patchbay,
      parameter_schema: %{},
      reserved_values: %{},
      route_spec_id: :patchbay
    },
    %Entry{
      path_pattern: "/keyfleet",
      live_action: :keyfleet,
      parameter_schema: %{},
      reserved_values: %{},
      route_spec_id: :keyfleet
    },
    %Entry{
      path_pattern: "/credits/refunds",
      live_action: :credits_refunds,
      parameter_schema: %{},
      reserved_values: %{},
      route_spec_id: :credits_refunds
    },
    %Entry{
      path_pattern: "/admin/credits",
      live_action: :credits_admin,
      parameter_schema: %{},
      reserved_values: %{},
      route_spec_id: :credits_admin
    }
  ]

  @specs %{
    home: {:home, nil, nil, "Regent", "/", [], :home, %{}},
    paper_pro_daily:
      {:paper_pro_daily, nil, nil, "Paper Pro Daily", "/paper-pro-daily", [], :home, %{}},
    app:
      {:app, :regent_ops, "Regents Labs", "Overview", "/app",
       [:wallet_status, :network_status, :profile_actions], :regents_labs, %{}},
    account:
      {:account, :regent_ops, "Regents Labs", "Account", "/app", [:profile_actions],
       :regents_labs, %{}},
    account_credits:
      {:account_credits, :regent_ops, "Regents Labs", "Purchase History", "/app",
       [:profile_actions], :regents_labs, %{}},
    account_points:
      {:account_points, :regent_ops, "Regents Labs", "Points", "/app", [:profile_actions],
       :regents_labs, %{}},
    regent_profile:
      {:regent_profile, :regent_ops, "Regents Labs", "Regent Profile", "/app",
       [:wallet_status, :network_status, :profile_actions], :regent_record, %{}},
    stake:
      {:stake, :regent_ops, "Regents Labs", "Stake", "/app",
       [:wallet_status, :network_status, :profile_actions], :regents_labs, %{}},
    redeem:
      {:redeem, :regent_ops, "Regents Labs", "Redeem", "/app",
       [:wallet_status, :network_status, :profile_actions], :regents_labs, %{}},
    redeem_gallery:
      {:redeem_gallery, :regent_ops, "Regents Labs", "Regents Club passes", "/app",
       [:profile_actions], :regents_labs, %{}},
    autolaunch:
      {:autolaunch, :regent_ops, "Regents Labs", "Autolaunch", "/app", [:profile_actions],
       :regents_labs, %{}},
    techtree:
      {:techtree, :regent_ops, "Regents Labs", "Techtree", "/app", [:profile_actions],
       :regents_labs, %{}},
    patchbay:
      {:patchbay, :regent_ops, "Regents Labs", "Patchbay", "/app", [:profile_actions],
       :regents_labs, %{}},
    keyfleet:
      {:keyfleet, :regent_ops, "Regents Labs", "Keyfleet", "/app", [:profile_actions],
       :regents_labs, %{}},
    credits_refunds:
      {:credits_refunds, :regent_ops, "Regents Labs", "Credits refunds", "/app",
       [:profile_actions], :regents_labs, %{}},
    credits_admin:
      {:credits_admin, :regent_ops, "Regents Labs", "Credits admin", "/app", [:profile_actions],
       :regents_labs, %{}}
  }

  def entries, do: @entries

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

  defp build_spec(action, params) do
    {route_id, app_id, app_label, page_label, root, controls, background, local_state} =
      Map.fetch!(@specs, action)

    %Spec{
      route_id: route_id,
      destination: destination(action, params),
      app_id: app_id,
      app_display_label: app_label,
      page_display_label: page_label,
      canonical_root: root,
      sidebar_model: sidebar_model(app_id),
      header_controls: controls,
      background_slot: background,
      scroll_policy: :top,
      local_state: local_state
    }
  end

  defp sidebar_model(nil), do: %SidebarModel{id: :public, targets: []}

  defp sidebar_model(:regent_ops) do
    %SidebarModel{
      id: :regent_ops,
      targets: [
        %RouteTarget{route_id: :app, label: "Overview", path: "/app"},
        %RouteTarget{route_id: :stake, label: "Stake", path: "/stake"},
        %RouteTarget{route_id: :redeem, label: "Redeem", path: "/redeem"},
        %RouteTarget{route_id: :account, label: "Account", path: "/account"},
        %ViewerProfileTarget{label: "Profile"},
        %SidebarHeading{label: "Products"},
        %RouteTarget{route_id: :autolaunch, label: "Autolaunch", path: "/autolaunch"},
        %RouteTarget{route_id: :techtree, label: "Techtree", path: "/techtree"},
        %RouteTarget{route_id: :patchbay, label: "Patchbay", path: "/patchbay"},
        %RouteTarget{route_id: :keyfleet, label: "Keyfleet", path: "/keyfleet"},
        %SidebarHeading{label: "Reading"},
        %PageTarget{route_id: :paper_pro_daily, label: "Daily Research", path: "/paper-pro-daily"}
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

  defp sidebar_target_handoff(%PageTarget{} = target) do
    %{
      "type" => "page",
      "route_id" => target.route_id,
      "label" => target.label,
      "destination" => target.path
    }
  end

  defp sidebar_target_handoff(%ViewerProfileTarget{} = target) do
    %{
      "type" => "viewer_profile",
      "label" => target.label,
      "destination" => "/regents/:viewer_slug"
    }
  end

  defp sidebar_target_handoff(%SidebarHeading{} = heading) do
    %{"type" => "heading", "label" => heading.label}
  end

  defp handoff_params(:regent_profile), do: %{"slug" => "regent"}
  defp handoff_params(_), do: %{}

  defp destination(:regent_profile, %{"slug" => slug}), do: "/regents/#{slug}"

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
