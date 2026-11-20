defmodule RegentsWeb.Keyfleet.RouteCatalog do
  @moduledoc """
  The pages Keyfleet's frame (`RegentsWeb.Keyfleet.Components.Shell`) draws,
  by the route the router matched, named by its live action: each page's
  route, its address and the sidebar beside it. So far only the reading pages
  (`RegentsWeb.Keyfleet.Components.Reading`), each listed in the sidebar beside
  every other.
  """

  alias RegentsWeb.Keyfleet.AgentGuides
  alias __MODULE__.{Entry, RouteTarget, SidebarModel, Spec}

  @entries [
    %Entry{route_id: :about, path_pattern: "/keyfleet/about", parameter_schema: %{}},
    %Entry{
      route_id: :opportunities,
      path_pattern: "/keyfleet/opportunities",
      parameter_schema: %{}
    },
    %Entry{route_id: :docs, path_pattern: "/keyfleet/docs", parameter_schema: %{}},
    %Entry{route_id: :changelog, path_pattern: "/keyfleet/changelog", parameter_schema: %{}},
    %Entry{route_id: :agents, path_pattern: "/keyfleet/agents", parameter_schema: %{}},
    %Entry{
      route_id: :agent,
      path_pattern: "/keyfleet/agents/:agent",
      parameter_schema: %{agent: :agent}
    },
    %Entry{route_id: :privacy, path_pattern: "/keyfleet/privacy", parameter_schema: %{}},
    %Entry{route_id: :terms, path_pattern: "/keyfleet/terms", parameter_schema: %{}}
  ]

  # The reading pages, listed beside every one of them.
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

  @doc """
  The page of the route the router matched, by its live action, with the
  parts of the address its pattern names as `params`. An address whose parts
  name no page is not found.
  """
  def fetch!(route_id, params) do
    %Entry{} = entry = Enum.find(@entries, &(&1.route_id == route_id))
    validate_params!(entry, params)

    %Spec{
      route_id: route_id,
      destination: destination(entry.path_pattern, params),
      app_id: :reading,
      background_slot: :product,
      sidebar_model: %SidebarModel{id: :reading, targets: @reading_targets}
    }
  end

  defp validate_params!(%Entry{parameter_schema: schema}, params) do
    valid? =
      Enum.all?(schema, fn {key, type} -> valid_parameter?(type, params[Atom.to_string(key)]) end)

    if valid?, do: :ok, else: raise(RegentsWeb.NotFoundError)
  end

  # An agent's page is one `RegentsWeb.Keyfleet.AgentGuides` has.
  defp valid_parameter?(:agent, value),
    do: is_binary(value) and "/keyfleet/agents/#{value}" in AgentGuides.paths()

  # A value is written into the path the way a browser sends it.
  defp destination(path_pattern, params) do
    path_pattern
    |> String.split("/")
    |> Enum.map_join("/", fn
      ":" <> key -> params |> Map.fetch!(key) |> URI.encode(&URI.char_unreserved?/1)
      segment -> segment
    end)
  end
end
