defmodule RegentsWeb.Keyfleet.PublicSeasonsController do
  @moduledoc """
  A fleet's settled seasons for anyone, signed in or not: the public record
  the agent's `seasons_list` and `seasons_picks` read
  (`RegentsWeb.Keyfleet.AgentTools.Seasons.Answer`). The list's query is `before`
  alone or nothing, one season's picks' `after` alone or nothing.
  """
  use RegentsWeb, :controller

  alias RegentsWeb.Keyfleet.AgentReply
  alias RegentsWeb.Keyfleet.AgentTools.Seasons.Answer

  def index(conn, _params), do: reply(conn, :list)
  def show(conn, _params), do: reply(conn, :season)

  defp reply(conn, op) do
    conn = conn |> fetch_query_params() |> put_resp_header("cache-control", "no-store")
    params = Map.merge(conn.query_params, conn.path_params)
    AgentReply.answer(conn, Answer.answer(op, params, nil, nil))
  end
end
