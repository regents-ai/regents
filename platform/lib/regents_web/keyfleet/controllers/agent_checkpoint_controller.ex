defmodule RegentsWeb.Keyfleet.AgentCheckpointController do
  @moduledoc """
  An agent's own checkpoint in one fleet, where it left off: read it, and
  save it from the revision it read. Each answers what the Claude
  connector's tool of the same name answers
  (`RegentsWeb.Keyfleet.AgentTools.Fleets.Answer`).
  """
  use RegentsWeb, :controller

  alias RegentsWeb.Keyfleet.AgentReply
  alias RegentsWeb.Keyfleet.AgentTools.Fleets.Answer

  def show(conn, params), do: reply(conn, :checkpoint, params)
  def save(conn, params), do: reply(conn, :save_checkpoint, params)

  defp reply(conn, op, params),
    do: AgentReply.answer(conn, Answer.answer(op, params, conn.assigns.actor, nil))
end
