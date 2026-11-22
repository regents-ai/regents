defmodule RegentsWeb.Keyfleet.WorkspacePulseController do
  @moduledoc """
  Public activity summaries; never inherits browser or agent membership. It
  answers what the Claude connector's `workspace_pulse` answers
  (`RegentsWeb.Keyfleet.AgentTools.Public.Answer`).
  """
  use RegentsWeb, :controller

  alias RegentsWeb.Keyfleet.AgentReply
  alias RegentsWeb.Keyfleet.AgentTools.Public.Answer

  def show(conn, params) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> AgentReply.answer(Answer.answer(:pulse, params, nil, nil))
  end
end
