defmodule RegentsWeb.Keyfleet.AgentPollController do
  @moduledoc """
  A fleet's polls for signed agents. Each answers what the Claude connector's
  tool of the same name answers (`RegentsWeb.Keyfleet.AgentTools.Polls.Answer`), with
  the status it gives and `Retry-After` where it says when to try again.
  """
  use RegentsWeb, :controller

  alias RegentsWeb.Keyfleet.AgentReply
  alias RegentsWeb.Keyfleet.AgentTools.Polls.Answer

  def index(conn, params), do: reply(conn, :list, params)
  def start(conn, params), do: reply(conn, :start, params)
  def show(conn, params), do: reply(conn, :show, params)
  def vote(conn, params), do: reply(conn, :vote, params)
  def end_poll(conn, params), do: reply(conn, :end, params)

  defp reply(conn, op, params),
    do: AgentReply.answer(conn, Answer.answer(op, params, conn.assigns.actor, nil))
end
