defmodule RegentsWeb.Keyfleet.AgentTools do
  @moduledoc """
  What an agent reads and does in a fleet where the answer joins several of
  the domains' reads or adds page addresses (`RegentsWeb.Keyfleet.AgentTools.Workspace`),
  also exposed through the unified `/mcp` server.
  """
  use Ash.Domain, otp_app: :regents, extensions: [AshAi]

  resources do
    resource RegentsWeb.Keyfleet.AgentTools.Workspace do
      define :workspace_show, action: :show, args: [:fleet_id, :id]
      define :workspace_board, action: :board, args: [:fleet_id]
      define :workspace_view, action: :view, args: [:fleet_id]
      define :workspace_changes, action: :changes, args: [:fleet_id]
      define :workspace_packet, action: :packet, args: [:fleet_id]
      define :atlas_swarm, action: :atlas, args: [:fleet_id]
      define :atlas_things, action: :atlas_things, args: [:fleet_id]
    end
  end

  tools do
    tool :keyfleet_workspace_show, RegentsWeb.Keyfleet.AgentTools.Workspace, :show do
      title("Keyfleet item")
      description "Reads one workspace item in a Keyfleet fleet."

      annotations(
        read_only_hint: true,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :keyfleet_workspace_board, RegentsWeb.Keyfleet.AgentTools.Workspace, :board do
      title("Keyfleet board")
      description "Reads a Keyfleet fleet's workspace board."

      annotations(
        read_only_hint: true,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :keyfleet_workspace_graph, RegentsWeb.Keyfleet.AgentTools.Workspace, :view do
      title("Keyfleet graph")
      description "Reads a Keyfleet fleet's workspace graph view."

      annotations(
        read_only_hint: true,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :keyfleet_workspace_changes, RegentsWeb.Keyfleet.AgentTools.Workspace, :changes do
      title("Keyfleet changes")
      description "Reads recent workspace changes in a Keyfleet fleet."

      annotations(
        read_only_hint: true,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :keyfleet_atlas_swarm, RegentsWeb.Keyfleet.AgentTools.Workspace, :atlas do
      title("Keyfleet Atlas")
      description "Reads a Keyfleet fleet's Atlas swarm state."

      annotations(
        read_only_hint: true,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end
  end
end
