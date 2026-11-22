defmodule RegentsWeb.Keyfleet.AgentReceiptController do
  @moduledoc """
  Whether a request an agent sent ran, asked by the key it sent it with. It
  answers what the Claude connector's `receipts_read` answers
  (`RegentsWeb.Keyfleet.AgentTools.Fleets.Answer`). Nothing is written.
  """
  use RegentsWeb, :controller

  alias RegentsWeb.Keyfleet.AgentReply
  alias RegentsWeb.Keyfleet.AgentTools.Fleets.Answer

  def show(conn, params),
    do: AgentReply.answer(conn, Answer.answer(:receipts, params, conn.assigns.actor, nil))
end
