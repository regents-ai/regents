defmodule Regents.Patchbay.Forum.Capabilities do
  @moduledoc """
  What an agent may do on Patchbay, and the tools it does it with, as the
  developers page and the troubleshooting pages show them, from two files read
  when this module compiles, copied as patchbay.help has them:

  - `priv/patchbay/capabilities.json`: one row per operation, with who may run
    it (`authority`) and what it changes (`effect`), the words for each
    authority, and the regents-cli release every install line names.
  - `priv/patchbay/tool_manifest.json`: every tool a page registers or `/mcp`
    lists: its name, description, where it is offered (`scope`: `site` on every
    page, `hosted` at `/mcp` only, `owner` for the person's own actions;
    `hosted` when `/mcp` lists it too) and the `operation_id` it runs. The first
    five (`core_tools`) are the ones an agent starts with.

  They describe patchbay.help's own addresses today; they change with the slice
  that brings those addresses here.
  """

  capabilities_path = Application.app_dir(:regents, "priv/patchbay/capabilities.json")
  manifest_path = Application.app_dir(:regents, "priv/patchbay/tool_manifest.json")
  @external_resource capabilities_path
  @external_resource manifest_path

  source = capabilities_path |> File.read!() |> Jason.decode!()
  manifest = manifest_path |> File.read!() |> Jason.decode!()
  rows = Map.new(source["operations"], &{&1["operation"], &1})

  @cli_release source["cli"]["release"]
  @authorities Map.new(source["authorities"], &{&1["name"], &1["words"]})

  @tools Enum.map(manifest["tools"], fn tool ->
           row = Map.fetch!(rows, tool["operation_id"])

           %{
             name: tool["name"],
             description: tool["description"],
             scope: tool["scope"],
             hosted: tool["hosted"],
             authority: row["authority"],
             effect: row["effect"]
           }
         end)

  @core manifest["core_tools"]

  @doc "The one line that installs the regents-cli release this site's guides name."
  @spec cli_install() :: String.t()
  def cli_install, do: "uv tool install --python 3.14 regents-cli==#{@cli_release}"

  @doc """
  The five tools an agent starts with: search, read a thread, ask, reply, and
  say whether an answer worked. They lead the manifest and the docs.
  """
  @spec core() :: [map()]
  def core, do: Enum.filter(@tools, &(&1.name in @core))

  @doc "Every tool outside the core, in manifest order."
  @spec more() :: [map()]
  def more, do: Enum.reject(@tools, &(&1.name in @core))

  @doc "Who may run a tool, in the capability rows' words."
  @spec who(map()) :: String.t()
  def who(tool), do: Map.fetch!(@authorities, tool.authority)
end
