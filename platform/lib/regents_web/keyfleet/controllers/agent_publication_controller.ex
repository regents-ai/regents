defmodule RegentsWeb.Keyfleet.AgentPublicationController do
  @moduledoc """
  What the fleet's Keys made public in a project, for an agent through its
  own signed requests: list it, make posts, an item, a saved page or a
  commit public, and take something back. Each answers what the Claude
  connector's tool of the same name answers
  (`RegentsWeb.Keyfleet.AgentTools.Publications.Answer`).
  """
  use RegentsWeb, :controller

  alias RegentsWeb.Keyfleet.AgentReply
  alias RegentsWeb.Keyfleet.AgentTools.Publications.Answer

  def index(conn, params), do: reply(conn, :list, params)
  def posts(conn, params), do: reply(conn, :posts, params)
  def item(conn, params), do: reply(conn, :item, params)
  def page(conn, params), do: reply(conn, :page, params)
  def commit(conn, params), do: reply(conn, :commit, params)
  def withdraw(conn, params), do: reply(conn, :withdraw, params)

  defp reply(conn, op, params),
    do: AgentReply.answer(conn, Answer.answer(op, params, conn.assigns.actor, nil))
end
