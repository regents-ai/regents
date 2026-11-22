defmodule RegentsWeb.Keyfleet.AgentDoctorController do
  @moduledoc """
  An agent's standing in one fleet, in one read. It answers what the Claude
  connector's `fleets_doctor` answers (`RegentsWeb.Keyfleet.AgentTools.Fleets.Answer`).
  """
  use RegentsWeb, :controller

  alias RegentsWeb.Keyfleet.AgentReply
  alias RegentsWeb.Keyfleet.AgentTools.Fleets.Answer

  def show(conn, params),
    do: AgentReply.answer(conn, Answer.answer(:doctor, params, conn.assigns.actor, nil))
end
