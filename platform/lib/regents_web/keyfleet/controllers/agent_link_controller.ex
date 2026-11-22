defmodule RegentsWeb.Keyfleet.AgentLinkController do
  @moduledoc """
  What a pasted Keyfleet address names, and the read to call next. It
  answers what the Claude connector's `links_resolve` answers
  (`RegentsWeb.Keyfleet.AgentTools.Fleets.Answer`). Nothing is written.
  """
  use RegentsWeb, :controller

  alias RegentsWeb.Keyfleet.AgentReply
  alias RegentsWeb.Keyfleet.AgentTools.Fleets.Answer

  def resolve(conn, params),
    do: AgentReply.answer(conn, Answer.answer(:link, params, conn.assigns.actor, nil))
end
