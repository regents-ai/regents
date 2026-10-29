defmodule RegentsWeb.AgentToolsCommandsTest do
  @moduledoc """
  A CLI command and its browser tool are one operation. Invariants: each command
  that names a browser tool sends the same request with the same authority and
  effect as that tool, and every signed tool can be prepared.
  """
  use ExUnit.Case, async: true

  @tools "priv/tool_manifest.json"
         |> File.read!()
         |> Jason.decode!()
         |> Map.fetch!("tools")
         |> Map.new(&{&1["name"], &1})

  @commands "../cli/commands.json"
            |> File.read!()
            |> Jason.decode!()
            |> Map.fetch!("commands")
            |> Enum.filter(& &1["webmcp"])

  # A command's authority, as the tool that does the same states it.
  @authority %{
    "public" => {"public", "none"},
    "signed_agent" => {"siwa_per_request", "siwa"},
    "paired_agent" => {"siwa_per_request", "siwa_and_pairing"}
  }

  test "each command with a browser tool sends the tool's request with its authority" do
    for command <- @commands do
      tool = Map.fetch!(@tools, command["webmcp"])

      assert tool["route"] == "#{command["method"]} #{command["path"]}", command["command"]
      assert tool["interfaces"]["webmcp"] == command["webmcp"], command["command"]
      assert tool["effect"] == command["effect"], command["command"]

      assert {tool["authentication"], tool["requires"]} ==
               Map.fetch!(@authority, command["authority"]),
             command["command"]
    end

    assert "regents_agent_status" in Enum.map(@commands, & &1["webmcp"])
  end

  test "every signed tool can be prepared, and nothing else can" do
    signed =
      for {name, %{"authentication" => "siwa_per_request"}} <- @tools,
          into: MapSet.new(),
          do: name

    prepared =
      @tools
      |> Map.fetch!("prepare_agent_request")
      |> get_in(["input_schema", "properties", "operation", "enum"])
      |> MapSet.new()

    assert prepared == signed
    assert "regents_agent_status" in prepared
  end
end
