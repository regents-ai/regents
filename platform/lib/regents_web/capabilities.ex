defmodule RegentsWeb.Capabilities do
  @moduledoc """
  What an agent may do on this site: one row per operation in the OpenAPI
  document, and one per tool only the hosted MCP server has, in
  `priv/capabilities.json`, in ash-template's shape.

  Each row says who may run the operation, on what conditions, where its person
  sees it and on which surfaces an agent reaches it: the browser tool from
  `priv/tool_manifest.json` (the file the pages register them from), the command
  from `cli/commands.json`, the address from `priv/public/openapi.json` and the
  hosted MCP tool from the AshAi `tools` block of the operation's domain. These
  are checked against each other when this module compiles: every surface an
  operation leaves out gives a reason, a surface is listed exactly where its
  tool, command or address is, and a hosted tool takes the browser tool's input.
  A tool only the hosted MCP server has, such as a connected app's identity
  tools, is named after its operation (`getIdentity` is `get_identity`). Each
  agent operation also says, in its person's words, what it lets an agent do,
  which the Account page shows.
  """

  paths = [
    source: Application.app_dir(:regents, "priv/capabilities.json"),
    manifest: Application.app_dir(:regents, "priv/tool_manifest.json"),
    openapi: Application.app_dir(:regents, "priv/public/openapi.json"),
    commands: Path.expand("../../../cli/commands.json", __DIR__)
  ]

  for {_name, path} <- paths, do: @external_resource(path)
  files = Map.new(paths, fn {name, path} -> {name, path |> File.read!() |> Jason.decode!()} end)

  @source files.source
  @agents ~w(signed_agent paired_agent)
  @connected_app "connected_app"

  openapi =
    for {path, methods} <- files.openapi["paths"],
        {method, %{"operationId" => id}} <- methods,
        into: %{},
        do: {id, {String.upcase(method), path}}

  # The browser tool for an operation is the one on its address; a tool on an
  # address with a path parameter, such as list_regents_webmcp_tools on
  # /api/v1/site-tools/{site}, is one of that operation's tools.
  on_route = fn tool, {method, path} ->
    pattern = Regex.compile!("^#{method} " <> Regex.replace(~r/\{[^}]+\}/, path, "[^/]+") <> "$")
    tool["route"] |> String.split(",") |> Enum.any?(&(&1 |> String.trim() =~ pattern))
  end

  tools = fn id ->
    Enum.filter(files.manifest["tools"], &(openapi[id] && on_route.(&1, openapi[id])))
  end

  commands = Map.new(files.commands["commands"], &{&1["operation_id"], &1})

  # The tools each domain hands AshAi for hosted MCP, by name, with the input
  # AshAi asks for: none for an action that takes nothing.
  hosted =
    for domain <- Application.compile_env!(:regents, :ash_domains),
        tool <- AshAi.Info.tools(domain),
        into: %{} do
      action = Ash.Resource.Info.action(tool.resource, tool.action)

      schema =
        AshAi.Tool.Schema.for_action(domain, tool.resource, action, nil, [], strict?: false)

      {Atom.to_string(tool.name),
       schema["properties"]["input"] || %{"type" => "object", "properties" => %{}}}
    end

  # An input's shape for comparing two schemas: each field's type, choices and
  # format, and which fields are required. Words and lengths are left out.
  shape = fn schema ->
    {Map.new(schema["properties"], fn {name, field} ->
       {name, Map.take(field, ~w(type enum format))}
     end), MapSet.new(schema["required"] || [])}
  end

  surface_names = ~w(webmcp hosted_mcp http cli)
  names = fn key -> MapSet.new(@source[key], & &1["name"]) end

  {authorities, conditions, switches} =
    {names.("authorities"), names.("conditions"), names.("switches")}

  listed = Enum.map(@source["operations"], & &1["operation"])

  unless length(listed) == length(Enum.uniq(listed)) and
           MapSet.subset?(MapSet.new(Map.keys(openapi)), MapSet.new(listed)),
         do: raise("priv/capabilities.json must list every OpenAPI operation once")

  @operations (for row <- @source["operations"] do
                 id = row["operation"]
                 surfaces = row["surfaces"]
                 tools = tools.(id)
                 command = commands[id]
                 # An operation the OpenAPI document leaves out is a tool only the
                 # hosted MCP server has, named after it.
                 hosted_only = !openapi[id] && Macro.underscore(id)
                 hosted_name = if hosted_only, do: hosted_only, else: Enum.at(tools, 0)["name"]

                 browser_input =
                   case tools do
                     [tool] -> tool["input_schema"]
                     _none_or_several -> nil
                   end

                 problem =
                   cond do
                     hosted_only &&
                         (!Map.has_key?(hosted, hosted_only) or surfaces["hosted_mcp"] != true or
                            Enum.any?(~w(webmcp http cli), &(surfaces[&1] == true)) or
                            !!command) ->
                       "no OpenAPI operation, and no hosted tool alone named after it"

                     row["authority"] not in authorities ->
                       "an unknown authority"

                     not Enum.all?(row["conditions"], &(&1 in conditions)) ->
                       "an unknown condition"

                     row["switch"] && row["switch"] not in switches ->
                       "an unknown switch"

                     row["may"] && row["authority"] not in @agents ->
                       "words for a person on an operation no agent runs"

                     Enum.any?(
                       tools,
                       &(&1["authentication"] == "siwa_per_request" !=
                             row["authority"] in @agents)
                     ) ->
                       "a browser tool signed differently"

                     command && command["effect"] != row["effect"] ->
                       "a command with another effect"

                     Map.keys(surfaces) |> Enum.sort() != Enum.sort(surface_names) or
                         not Enum.all?(
                           Map.values(surfaces),
                           &(&1 == true or (is_binary(&1) and &1 != ""))
                         ) ->
                       "a surface left out with no reason"

                     surfaces["webmcp"] == true != (tools != []) or
                       surfaces["cli"] == true != !!command or
                         surfaces["http"] == true != !!openapi[id] ->
                       "a surface listed differently from its tool, command or address"

                     surfaces["hosted_mcp"] == true && !hosted_only &&
                         (not match?([_], tools) or !Map.has_key?(hosted, hosted_name) or
                            shape.(hosted[hosted_name]) != shape.(browser_input)) ->
                       "a hosted tool that is not its one browser tool, or takes other input"

                     "site_oauth" in row["auth_modes"] !=
                         (row["authority"] == @connected_app or
                            (row["authority"] in @agents and surfaces["hosted_mcp"] == true)) ->
                       "proof that differs from its authority"

                     true ->
                       nil
                   end

                 if problem, do: raise("#{id} in priv/capabilities.json has #{problem}")

                 %{
                   operation: id,
                   authority: row["authority"],
                   may: row["may"],
                   hosted_mcp: if(surfaces["hosted_mcp"] == true, do: hosted_name)
                 }
               end)

  unless MapSet.new(@operations, & &1.hosted_mcp) |> MapSet.delete(nil) ==
           MapSet.new(Map.keys(hosted)),
         do:
           raise(
             "priv/capabilities.json must mark hosted_mcp on exactly the operations whose " <>
               "browser tool, or own name, is an AshAi tool"
           )

  # Every signed browser tool says what it lets an agent do, or is about the agent
  # itself, so a new signed tool cannot reach agents without its words.
  for %{"authentication" => "siwa_per_request", "route" => route} = tool <-
        files.manifest["tools"],
      row =
        Enum.find(@operations, &(openapi[&1.operation] && on_route.(tool, openapi[&1.operation]))),
      !row or (row.authority == "paired_agent" and !row.may),
      do:
        raise(
          "#{tool["name"]} on #{route} must have its operation's words in priv/capabilities.json"
        )

  @hosted for row <- @operations, name = row.hosted_mcp, do: String.to_atom(name)

  @doc "The hosted MCP server's tools, by the name AshAi gives each."
  @spec hosted_tools() :: [atom()]
  def hosted_tools, do: @hosted

  @may @operations |> Enum.map(& &1.may) |> Enum.reject(&is_nil/1) |> Enum.uniq()

  @doc "What a paired agent may do on this site, in its person's words, a line each."
  @spec may() :: [String.t()]
  def may, do: @may
end
