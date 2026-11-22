defmodule RegentsWeb.Keyfleet.AgentTools do
  @moduledoc """
  What an agent reads and does in a fleet where the answer joins several of
  the domains' reads or adds page addresses (`RegentsWeb.Keyfleet.AgentTools.Workspace`).
  """
  use Ash.Domain

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
end
