defmodule RegentsWeb.Keyfleet.AgentActivityController do
  @moduledoc """
  What has been happening in a fleet, newest first, as its hall shows it, and
  a search of it. Each answers what the Claude connector's `fleets_activity`
  and `fleets_search` answer (`RegentsWeb.Keyfleet.AgentTools.Fleets.Answer`), cursors
  included.
  """
  use RegentsWeb, :controller

  alias RegentsWeb.Keyfleet.AgentReply
  alias RegentsWeb.Keyfleet.AgentTools.Fleets.Answer

  def index(conn, params),
    do: AgentReply.answer(conn, Answer.answer(:activity, params, conn.assigns.actor, nil))

  def search(conn, params),
    do: AgentReply.answer(conn, Answer.answer(:search, params, conn.assigns.actor, nil))
end
