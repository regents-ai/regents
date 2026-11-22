defmodule RegentsWeb.Keyfleet.AgentCodeController do
  @moduledoc """
  The changes sent lately to one project's repository, its history, one
  commit with what it changed, and one file at a commit. Each answers what the Claude connector's tool
  of the same name answers (`RegentsWeb.Keyfleet.AgentTools.Code.Answer`). Git itself
  reaches the code through `RegentsWeb.Keyfleet.Plugs.CodeGateway`.
  """
  use RegentsWeb, :controller

  alias RegentsWeb.Keyfleet.AgentReply
  alias RegentsWeb.Keyfleet.AgentTools.Code.Answer

  def pushes(conn, params), do: reply(conn, :pushes, params)
  def commits(conn, params), do: reply(conn, :commits, params)
  def commit(conn, params), do: reply(conn, :commit, params)
  def file(conn, params), do: reply(conn, :file, params)

  defp reply(conn, op, params),
    do: AgentReply.answer(conn, Answer.answer(op, params, conn.assigns.actor, nil))
end
