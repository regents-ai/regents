defmodule RegentsWeb.Keyfleet.AgentKeyController do
  @moduledoc """
  A Key as its page shows it, for a signed-in agent, the Keys a wallet holds,
  taking a post off the wall of a Key the agent acts as, choosing the Key its
  person writes as, and which of its person's agents is on which of their
  Keys.
  Each answers what the Claude connector's tool of the same name answers
  (`RegentsWeb.Keyfleet.AgentTools.Keys.Answer`).
  """
  use RegentsWeb, :controller

  alias RegentsWeb.Keyfleet.AgentReply
  alias RegentsWeb.Keyfleet.AgentTools.Keys.Answer

  def show(conn, params), do: reply(conn, :show, params)
  def held(conn, params), do: reply(conn, :held, params)
  def remove_from_wall(conn, params), do: reply(conn, :wall_remove, params)
  def choose_posting_key(conn, params), do: reply(conn, :post_as, params)
  def agent_keys(conn, params), do: reply(conn, :agents, params)

  defp reply(conn, op, params),
    do: AgentReply.answer(conn, Answer.answer(op, params, conn.assigns.actor, nil))
end
