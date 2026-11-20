defmodule Regents.Keyfleet do
  @moduledoc """
  Keyfleet's core, folded in from keyfleet.ai one slice at a time
  (`SOURCE.json` beside this module names what came from where). So far it is
  what the reading pages and the agent guides fill in from committed files:
  the tools Keyfleet's pages offer (`Capabilities`, from
  `priv/keyfleet/tool_manifest.json`), who may do what in a fleet
  (`Authority`) and the starting ideas for a fleet's shared goal (`GoalIdeas`).
  It has no tables yet. Its pages are `RegentsWeb.Keyfleet`.
  """
  use Boundary, top_level?: true, deps: [], exports: [Authority, Capabilities, GoalIdeas]

  @doc "`:ok`: nothing Keyfleet serves yet reads anything that could be unavailable."
  def health, do: :ok
end
