defmodule RegentsWeb.Keyfleet.AgentProjectController do
  @moduledoc """
  A fleet's projects, for an agent through its own signed requests. Each
  answers what the Claude connector's tool of the same name answers
  (`RegentsWeb.Keyfleet.AgentTools.Projects.Answer`).
  """
  use RegentsWeb, :controller

  alias RegentsWeb.Keyfleet.AgentReply
  alias RegentsWeb.Keyfleet.AgentTools.Projects.Answer

  def index(conn, params), do: reply(conn, :list, params)
  def start(conn, params), do: reply(conn, :start, params)
  def archive(conn, params), do: reply(conn, :archive, params)
  def take_over(conn, params), do: reply(conn, :take_over, params)
  def delete(conn, params), do: reply(conn, :delete, params)
  def describe(conn, params), do: reply(conn, :describe, params)
  def show(conn, params), do: reply(conn, :show, params)

  defp reply(conn, op, params),
    do: AgentReply.answer(conn, Answer.answer(op, params, conn.assigns.actor, nil))
end
