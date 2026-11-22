defmodule RegentsWeb.Autolaunch.AgentNotPairedError do
  @moduledoc """
  An agent's pairing names a Privy user with no Regent account, when the shared
  agent requests (`RegentAgents.HTTP`) ask this site for it
  (`Regents.Autolaunch.Agents.paired_account/1`). Every pairing here is made by a
  signed-in person, whose Regent account exists from that sign-in, so such a
  pairing pairs the agent with no account. The agent gets 403
  `agent_not_paired` (`RegentsWeb.ErrorJSON`), as the site's own agent
  routes answer it (`RegentsWeb.Autolaunch.Plugs.AgentAccess`).
  """
  defexception message: "the agent's pairing names no Regent account", plug_status: 403
end
