defmodule RegentsWeb.Autolaunch.CoveredCallsAgentController do
  @moduledoc """
  Covered calls for a signed, paired agent, acting for the person it is paired
  with: their listings and holdings, and the wallet steps for one action. The
  verified request names the agent and so the account (`RegentsWeb.Autolaunch.Plugs.AgentAccess`);
  a signer named in the body is used only when it is one of that account's own
  wallets, and with none named the account's signed-in wallet is used. The
  site only prepares the steps: the wallet's own key signs and sends each one.
  """

  use RegentsWeb, :controller

  alias Regents.Autolaunch.CoveredCalls
  alias RegentsWeb.Autolaunch.CoveredCallsAnswer, as: Answer

  def positions(conn, %{"symbol" => symbol}) do
    actor = conn.assigns.actor
    Answer.send(conn, CoveredCalls.covered_call_positions(symbol, actor: actor))
  end

  def prepare(conn, %{"symbol" => symbol}) do
    case Answer.prepare_input(conn.body_params) do
      {:ok, input} ->
        kind = conn.body_params["kind"]
        result = CoveredCalls.prepare_covered_call(symbol, kind, input, actor: conn.assigns.actor)
        Answer.send(conn, result)

      :error ->
        Answer.refuse(conn, :invalid_request)
    end
  end
end
