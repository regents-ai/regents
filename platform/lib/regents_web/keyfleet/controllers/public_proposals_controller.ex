defmodule RegentsWeb.Keyfleet.PublicProposalsController do
  @moduledoc """
  Public indexed proposal discovery using the human list's existing read. It
  answers what the Claude connector's `proposals_list` answers
  (`RegentsWeb.Keyfleet.AgentTools.Public.Answer`): the query is `before` alone or
  nothing.
  """
  use RegentsWeb, :controller

  alias RegentsWeb.Keyfleet.AgentReply
  alias RegentsWeb.Keyfleet.AgentTools.Public.Answer

  def index(conn, _params) do
    conn = conn |> fetch_query_params() |> put_resp_header("cache-control", "no-store")
    params = Map.put(conn.query_params, "fleet_id", conn.path_params["fleet_id"])
    AgentReply.answer(conn, Answer.answer(:proposals, params, nil, nil))
  end
end
