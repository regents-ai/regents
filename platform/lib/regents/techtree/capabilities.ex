defmodule Regents.Techtree.Capabilities do
  @moduledoc """
  Techtree's canonical tool manifest, read at compile time from
  `priv/techtree/tool_manifest.json`, feeding `/api/v1/techtree/capabilities`,
  `/techtree/capabilities.json`, hosted MCP metadata, and browser tool docs.
  """

  @manifest_path Application.app_dir(:regents, "priv/techtree/tool_manifest.json")
  @external_resource @manifest_path
  @manifest @manifest_path |> File.read!() |> Jason.decode!()
  @tools Map.fetch!(@manifest, "tools")

  @doc "The complete Techtree tool manifest."
  @spec manifest() :: map()
  def manifest, do: @manifest

  @doc "All Techtree tools in manifest order."
  @spec tools() :: [map()]
  def tools, do: @tools

  @doc "Public browser tools registered via WebMCP (`document.modelContext`)."
  @spec webmcp_tools() :: [%{name: String.t(), title: String.t(), description: String.t()}]
  def webmcp_tools do
    for tool <- @tools, get_in(tool, ["interfaces", "webmcp"]) != nil do
      %{
        name: tool["name"],
        title: tool["title"],
        description: tool["description"]
      }
    end
  end
end
