defmodule RegentsWeb.Keyfleet.TreasuryController do
  @moduledoc """
  Public treasury figures shared with the fleet page; no wallet authority. It
  answers what the Claude connector's `treasury_show` answers
  (`RegentsWeb.Keyfleet.AgentTools.Public.Answer`).
  """
  use RegentsWeb, :controller

  alias RegentsWeb.Keyfleet.AgentReply
  alias RegentsWeb.Keyfleet.AgentTools.Public.Answer

  def show(conn, params) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> AgentReply.answer(Answer.answer(:treasury, params, nil, nil))
  end
end
