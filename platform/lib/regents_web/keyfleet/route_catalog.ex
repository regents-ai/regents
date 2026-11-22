defmodule RegentsWeb.Keyfleet.RouteCatalog do
  @moduledoc "Canonical behavior metadata for the route allowlist."

  alias Regents.Keyfleet.Fleets
  alias RegentsWeb.Keyfleet.AgentGuides
  alias RegentsWeb.NotFoundError

  alias __MODULE__.{
    Entry,
    RouteTarget,
    SidebarModel,
    Spec
  }

  @slug ~r/\A[a-z0-9][a-z0-9-]{0,62}\z/
  # Eighteen digits at most, so every admitted key number is a database integer.
  @token_id ~r/\A[1-9][0-9]{0,17}\z/
  # A workspace item is named by its type and its number, such as `task#12`.
  @object_id ~r/\A[a-z][a-z_]{0,31}#[1-9][0-9]{0,17}\z/
  # Eighteen digits at most, so every admitted proposal number is a database integer.
  @number ~r/\A[1-9][0-9]{0,17}\z/
  # A poll is named by its id, a UUID in lower case.
  @poll_id ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/
  # A project's repository is named by its fleet's id, then, for any project
  # but `general`, a hyphen and the project's name.
  @repository ~r/\A[a-z0-9_]{1,64}(-[a-z0-9]+)*\z/
  # A project is named as `Regents.Keyfleet.Projects.Project` names it.
  @project ~r/\A[a-z0-9]+(-[a-z0-9]+)*\z/
  # A commit is named by its full hash, as git writes it.
  @commit ~r/\A([0-9a-f]{40}|[0-9a-f]{64})\z/

  @pages [
    %Entry{
      path_pattern: "/keyfleet/about",
      live_action: :about,
      parameter_schema: %{},
      reserved_values: %{},
      route_spec_id: :about
    },
    %Entry{
      path_pattern: "/keyfleet/opportunities",
      live_action: :opportunities,
      parameter_schema: %{},
      reserved_values: %{},
      route_spec_id: :opportunities
    },
    %Entry{
      path_pattern: "/keyfleet/docs",
      live_action: :docs,
      parameter_schema: %{},
      reserved_values: %{},
      route_spec_id: :docs
    },
    %Entry{
      path_pattern: "/keyfleet/changelog",
      live_action: :changelog,
      parameter_schema: %{},
      reserved_values: %{},
      route_spec_id: :changelog
    },
    %Entry{
      path_pattern: "/keyfleet/agents",
      live_action: :agents,
      parameter_schema: %{},
      reserved_values: %{},
      route_spec_id: :agents
    },
    %Entry{
      path_pattern: "/keyfleet/agents/:agent",
      live_action: :agent,
      parameter_schema: %{agent: :agent},
      reserved_values: %{},
      route_spec_id: :agent
    },
    %Entry{
      path_pattern: "/keyfleet/privacy",
      live_action: :privacy,
      parameter_schema: %{},
      reserved_values: %{},
      route_spec_id: :privacy
    },
    %Entry{
      path_pattern: "/keyfleet/terms",
      live_action: :terms,
      parameter_schema: %{},
      reserved_values: %{},
      route_spec_id: :terms
    }
  ]

  # The pages every fleet has, each under the fleet's own address
  # (`Regents.Keyfleet.Fleets.path/1`): the fleet's page itself, whose hall also opens
  # its rooms (`?room=`), then its workspace and its code, each project's page,
  # proposals, treasury, polls and record of seasons, its search, and each of
  # its Keys' pages and messages.
  @fleet_pages [
    {"", :fleet, %{}},
    {"/workspace", :workspace, %{}},
    {"/workspace/:object_id", :workspace_item, %{object_id: :object_id}},
    {"/code/:repository/commits/:commit", :code_commit,
     %{repository: :repository, commit: :commit}},
    {"/code/:repository/commits", :code_history, %{repository: :repository}},
    {"/code/:repository/files", :code_files, %{repository: :repository}},
    {"/projects/:project", :project, %{project: :project}},
    {"/proposals", :proposals, %{}},
    {"/proposals/:number", :proposal, %{number: :number}},
    {"/treasury", :treasury, %{}},
    {"/polls", :polls, %{}},
    {"/polls/:poll_id", :poll, %{poll_id: :poll_id}},
    {"/seasons", :seasons, %{}},
    {"/search", :search, %{}},
    {"/worldline", :worldline, %{}},
    {"/atlas", :atlas, %{}},
    {"/keys/:token_id", :keys, %{token_id: :token_id}},
    {"/keys/:token_id/dms", :dms, %{token_id: :token_id}},
    {"/keys/:token_id/dms/:other_token_id", :dm,
     %{token_id: :token_id, other_token_id: :token_id}}
  ]

  @entries @pages ++
             for(
               %{id: fleet_id, path: path} <- Fleets.catalog(),
               {under, action, schema} <- @fleet_pages,
               do: %Entry{
                 path_pattern: path <> under,
                 fleet_id: fleet_id,
                 live_action: action,
                 parameter_schema: schema,
                 reserved_values: %{},
                 route_spec_id: action
               }
             )

  @specs %{
    about: {:about, :reading, "Keyfleet", "About", "/", [:profile_actions], :product, %{}},
    opportunities:
      {:opportunities, :reading, "Keyfleet", "Opportunities", "/", [:profile_actions], :product,
       %{}},
    docs: {:docs, :reading, "Keyfleet", "Docs", "/", [:profile_actions], :product, %{}},
    changelog:
      {:changelog, :reading, "Keyfleet", "Changelog", "/", [:profile_actions], :product, %{}},
    agents: {:agents, :reading, "Keyfleet", "Agents", "/", [:profile_actions], :product, %{}},
    agent: {:agent, :reading, "Keyfleet", "Agents", "/", [:profile_actions], :product, %{}},
    privacy: {:privacy, :reading, "Keyfleet", "Privacy", "/", [:profile_actions], :product, %{}},
    terms: {:terms, :reading, "Keyfleet", "Terms", "/", [:profile_actions], :product, %{}},
    fleet: {:fleet, :product, "Keyfleet", "Fleet", "/", [:profile_actions], :product, %{}},
    keys: {:keys, :product, "Keyfleet", "Key", "/", [:profile_actions], :product, %{}},
    dms: {:dms, :product, "Keyfleet", "Messages", "/", [:profile_actions], :product, %{}},
    dm: {:dm, :product, "Keyfleet", "Messages", "/", [:profile_actions], :product, %{}},
    workspace:
      {:workspace, :product, "Keyfleet", "Workspace", "/", [:profile_actions], :product, %{}},
    workspace_item:
      {:workspace_item, :product, "Keyfleet", "Workspace", "/", [:profile_actions], :product, %{}},
    code_commit:
      {:code_commit, :product, "Keyfleet", "Workspace", "/", [:profile_actions], :product, %{}},
    code_history:
      {:code_history, :product, "Keyfleet", "Workspace", "/", [:profile_actions], :product, %{}},
    code_files:
      {:code_files, :product, "Keyfleet", "Workspace", "/", [:profile_actions], :product, %{}},
    project: {:project, :product, "Keyfleet", "Project", "/", [:profile_actions], :product, %{}},
    proposals:
      {:proposals, :product, "Keyfleet", "Proposals", "/", [:profile_actions], :product, %{}},
    proposal:
      {:proposal, :product, "Keyfleet", "Proposals", "/", [:profile_actions], :product, %{}},
    treasury:
      {:treasury, :product, "Keyfleet", "Treasury", "/", [:profile_actions], :product, %{}},
    polls: {:polls, :product, "Keyfleet", "Polls", "/", [:profile_actions], :product, %{}},
    poll: {:poll, :product, "Keyfleet", "Polls", "/", [:profile_actions], :product, %{}},
    seasons: {:seasons, :product, "Keyfleet", "Seasons", "/", [:profile_actions], :product, %{}},
    search: {:search, :product, "Keyfleet", "Search", "/", [:profile_actions], :product, %{}},
    worldline:
      {:worldline, :product, "Keyfleet", "Worldline", "/", [:profile_actions], :product, %{}},
    atlas: {:atlas, :product, "Keyfleet", "Atlas", "/", [:profile_actions], :product, %{}}
  }

  # The reading pages (`RegentsWeb.Keyfleet.Components.Reading`), listed beside every one
  # of them.
  @reading_targets [
    %RouteTarget{route_id: :agents, label: "Agents", path: "/keyfleet/agents"},
    %RouteTarget{route_id: :docs, label: "Docs", path: "/keyfleet/docs"},
    %RouteTarget{route_id: :changelog, label: "Changelog", path: "/keyfleet/changelog"},
    %RouteTarget{route_id: :about, label: "About", path: "/keyfleet/about"},
    %RouteTarget{
      route_id: :opportunities,
      label: "Opportunities",
      path: "/keyfleet/opportunities"
    },
    %RouteTarget{route_id: :privacy, label: "Privacy", path: "/keyfleet/privacy"},
    %RouteTarget{route_id: :terms, label: "Terms", path: "/keyfleet/terms"}
  ]

  def entries, do: @entries

  @doc """
  The page at the route `path_pattern`, as the router names the route an
  address matched, with the parts of the address the pattern names as
  `params`. A fleet's pages are at the fleet's own address
  (`Regents.Keyfleet.Fleets.path/1`) and nowhere else; the spec names that fleet as
  `fleet_id`.
  """
  def fetch!(path_pattern, params \\ %{}) do
    entry = Enum.find(@entries, &(&1.path_pattern == path_pattern)) || raise(NotFoundError)
    validate_params!(entry, params)
    build_spec(entry.route_spec_id, destination(path_pattern, params), entry.fleet_id)
  end

  @doc """
  The address that opens the fleet `fleet_id`'s notebooks for a holder of one
  of its Keys, then returns to `/`.
  """
  def notebooks_path(fleet_id),
    do: "/keyfleet/fleets/#{fleet_id}/notebooks/open?" <> URI.encode_query(to: "/")

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
  defp valid_parameter?(:token_id, value), do: is_binary(value) and Regex.match?(@token_id, value)

  defp valid_parameter?(:number, value), do: is_binary(value) and Regex.match?(@number, value)

  defp valid_parameter?(:poll_id, value),
    do: is_binary(value) and Regex.match?(@poll_id, value)

  defp valid_parameter?(:object_id, value),
    do: is_binary(value) and Regex.match?(@object_id, value)

  defp valid_parameter?(:repository, value),
    do: is_binary(value) and Regex.match?(@repository, value)

  defp valid_parameter?(:project, value),
    do: is_binary(value) and String.length(value) <= 32 and Regex.match?(@project, value)

  defp valid_parameter?(:commit, value), do: is_binary(value) and Regex.match?(@commit, value)

  # An agent's page is one `RegentsWeb.Keyfleet.AgentGuides` has.
  defp valid_parameter?(:agent, value),
    do: is_binary(value) and "/keyfleet/agents/#{value}" in AgentGuides.paths()

  defp build_spec(route_spec_id, destination, fleet_id) do
    {route_id, app_id, app_label, page_label, root, controls, background, local_state} =
      Map.fetch!(@specs, route_spec_id)

    %Spec{
      route_id: route_id,
      destination: destination,
      fleet_id: fleet_id,
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

  defp sidebar_model(:reading), do: %SidebarModel{id: :reading, targets: @reading_targets}

  # The fleets the sidebar links to, each to the fleet's page, then the account page.
  defp sidebar_model(:product) do
    fleets =
      for %{sidebar: :link, name: name, path: path} <- Fleets.catalog(),
          do: %RouteTarget{route_id: :fleet, label: name, path: path}

    %SidebarModel{
      id: :product,
      targets: fleets ++ [%RouteTarget{route_id: :account, label: "Account", path: "/account"}]
    }
  end

  # The handoff describes routes, not visits, so a parameterised route hands over
  # the pattern its paths are built from.
  defp handoff_route(entry) do
    spec = build_spec(entry.route_spec_id, entry.path_pattern, nil)

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
    %{"id" => sidebar.id, "targets" => Enum.map(sidebar.targets, &target_handoff/1)}
  end

  defp target_handoff(%RouteTarget{} = target) do
    %{
      "type" => "route",
      "route_id" => target.route_id,
      "label" => target.label,
      "destination" => target.path
    }
  end

  # A value is written into the path the way a browser sends it, so an item
  # such as `task#12` is `task%2312`.
  defp destination(path_pattern, params) do
    path_pattern
    |> String.split("/")
    |> Enum.map_join("/", fn
      ":" <> key -> params |> Map.fetch!(key) |> URI.encode(&URI.char_unreserved?/1)
      segment -> segment
    end)
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
