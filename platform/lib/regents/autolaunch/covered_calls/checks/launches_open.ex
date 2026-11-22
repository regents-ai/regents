defmodule Regents.Autolaunch.CoveredCalls.Checks.LaunchesOpen do
  @moduledoc """
  Holds once the site has left prelaunch read-only mode
  (`Regents.Autolaunch.Prelaunch.read_only?/0`). Until then no agent surface prepares
  wallet steps: the HTTP steps route is refused before the router
  (`RegentsWeb.Autolaunch.Prelaunch`), and this keeps the hosted MCP tool that runs the
  same operation from being listed or run.
  """
  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_opts), do: "the site has left prelaunch read-only mode"

  @impl true
  def match?(_actor, _context, _opts), do: not Regents.Autolaunch.Prelaunch.read_only?()
end
