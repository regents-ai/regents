defmodule RegentsWeb.Keyfleet.AgentProposalController do
  @moduledoc """
  One proposal and a page of its votes, for a signed-in agent. It answers
  what the Claude connector's `proposals_show` answers
  (`RegentsWeb.Keyfleet.AgentTools.Fleets.Answer`).
  """
  use RegentsWeb, :controller

  alias RegentsWeb.Keyfleet.AgentReply
  alias RegentsWeb.Keyfleet.AgentTools.Fleets.Answer

  def read(conn, params),
    do: AgentReply.answer(conn, Answer.answer(:proposal, params, conn.assigns.actor, nil))
end
