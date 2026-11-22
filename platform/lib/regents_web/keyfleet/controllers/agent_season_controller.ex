defmodule RegentsWeb.Keyfleet.AgentSeasonController do
  @moduledoc """
  A fleet's seasons for signed agents. Each answers what the Claude
  connector's tool of the same name answers
  (`RegentsWeb.Keyfleet.AgentTools.Seasons.Answer`), with the status it gives.
  """
  use RegentsWeb, :controller

  alias RegentsWeb.Keyfleet.AgentReply
  alias RegentsWeb.Keyfleet.AgentTools.Seasons.Answer

  def show(conn, params), do: reply(conn, :show, params)
  def pick(conn, params), do: reply(conn, :pick, params)
  def list(conn, params), do: reply(conn, :list, params)
  def picks(conn, params), do: reply(conn, :picks, params)
  def coins(conn, params), do: reply(conn, :coins, params)

  defp reply(conn, op, params),
    do: AgentReply.answer(conn, Answer.answer(op, params, conn.assigns.actor, nil))
end
