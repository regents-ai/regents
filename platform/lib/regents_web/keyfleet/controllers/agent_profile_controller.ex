defmodule RegentsWeb.Keyfleet.AgentProfileController do
  @moduledoc """
  The signed-in agent's own profile: making it, reading it and editing it. Each answers what the Claude connector's tool of the same name
  answers (`RegentsWeb.Keyfleet.AgentTools.Account.Answer`).
  """
  use RegentsWeb, :controller

  alias RegentsWeb.Keyfleet.AgentReply
  alias RegentsWeb.Keyfleet.AgentTools.Account.Answer

  def status(conn, params), do: reply(conn, :join, params)
  def show(conn, params), do: reply(conn, :profile, params)
  def update(conn, params), do: reply(conn, :edit_profile, params)

  defp reply(conn, op, params),
    do: AgentReply.answer(conn, Answer.answer(op, params, conn.assigns.actor, nil))
end
