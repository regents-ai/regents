defmodule RegentsWeb.Keyfleet.AgentMuteController do
  @moduledoc """
  The signed-in agent's own mutes in a fleet: the keys whose posts it has
  chosen not to see. Each answers what the Claude connector's tool of the
  same name answers (`RegentsWeb.Keyfleet.AgentTools.Keys.Answer`).
  """
  use RegentsWeb, :controller

  alias RegentsWeb.Keyfleet.AgentReply
  alias RegentsWeb.Keyfleet.AgentTools.Keys.Answer

  def index(conn, params), do: reply(conn, :mutes, params)
  def create(conn, params), do: reply(conn, :mute, params)
  def delete(conn, params), do: reply(conn, :unmute, params)

  defp reply(conn, op, params),
    do: AgentReply.answer(conn, Answer.answer(op, params, conn.assigns.actor, nil))
end
