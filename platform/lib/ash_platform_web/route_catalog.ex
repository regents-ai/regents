defmodule AshPlatformWeb.RouteCatalog do
  @moduledoc "Canonical behavior metadata for the founder-approved route allowlist."

  alias AshPlatformWeb.NotFoundError

  alias __MODULE__.{
    Entry,
    RouteTarget,
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
      path_pattern: "/app",
      live_action: :app,
      parameter_schema: %{},
      reserved_values: %{},
      route_spec_id: :app
    },
    #     %Entry{
    #       path_pattern: "/settings",
    #       live_action: :settings,
    #       parameter_schema: %{},
    #       reserved_values: %{},
    #       route_spec_id: :settings
    #     },
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
      path_pattern: "/regents-club/metadata-cutover",
      live_action: :regents_club_metadata,
      parameter_schema: %{},
      reserved_values: %{},
      route_spec_id: :regents_club_metadata
    }
  ]

  @specs %{
    home: {:home, nil, nil, "Regent", "/", [], :home, :landing, %{}},
    app:
      {:app, :regent_ops, "Regents Labs", "Overview", "/app",
       [:wallet_status, :network_status, :profile_actions], :regents_labs, :overview, %{}},
    #     settings:
    #       {:settings, :regent_ops, "Regents Labs", "Settings", "/app", [:profile_actions],
    #        :regents_labs, :detail, %{}},
    formation:
      {:formation, :formation, "Nous Portal", "Formation", "/formation", [:profile_actions],
       :formation, :lifecycle, %{}},
    regent_profile:
      {:regent_profile, :regent_ops, "Regents Labs", "Regent Profile", "/app",
       [:wallet_status, :network_status, :profile_actions], :regent_record, :detail, %{}},
    stake:
      {:stake, :regent_ops, "Regents Labs", "Stake", "/app",
       [:wallet_status, :network_status, :profile_actions], :regents_labs, :workflow, %{}},
    redeem:
      {:redeem, :regent_ops, "Regents Labs", "Redeem", "/app",
       [:wallet_status, :network_status, :profile_actions], :regents_labs, :workflow, %{}},
    regents_club_metadata:
      {:regents_club_metadata, :regent_ops, "Regents Labs", "Regents Club Metadata", "/app",
       [:wallet_status, :network_status, :profile_actions], :regents_labs, :workflow, %{}}
  }

  def entries, do: @entries

  def fetch!(action, params \\ %{}) do
    entry = Enum.find(@entries, &(&1.live_action == action)) || raise(NotFoundError)
    validate_params!(entry, params)
    build_spec(entry.route_spec_id, params)
  end

  def design_handoff do
    routes = Enum.reject(@entries, &(&1.route_spec_id == :regents_club_metadata))

    json =
      %{"schema_version" => 1, "routes" => Enum.map(routes, &handoff_route/1)}
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
    {route_id, app_id, app_label, page_label, root, controls, background, transition, local_state} =
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

  defp sidebar_target_handoff(%ViewerProfileTarget{} = target) do
    %{
      "type" => "viewer_profile",
      "label" => target.label,
      "destination" => "/regents/:viewer_slug"
    }
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
