defmodule RegentsWeb.Autolaunch.AgentPaymentController do
  @moduledoc """
  Payments into a launched token's revenue split for a signed, paired agent,
  acting for the person it is paired with: the steps of one payment or sweep
  on a token the site lists, named by its id as `autolaunch_tokens` lists it.
  The verified request names the agent and so the account
  (`RegentsWeb.Account.PairedAgent`); a signer named in the body is used only
  when it is one of that account's own wallets, and with none named the
  account's signed-in wallet is used. The site only prepares the steps: the
  wallet's own key signs and sends them (`Regents.Autolaunch.AgentPayment`).
  """

  use RegentsWeb, :controller

  alias RegentsWeb.Autolaunch.AgentPaymentAnswer, as: Answer

  def prepare(conn, %{"token_id" => token_id}) do
    case Answer.input(conn.body_params) do
      {:ok, input} ->
        Answer.send(
          conn,
          Regents.Autolaunch.prepare_payment(Map.put(input, "token_id", token_id),
            actor: conn.assigns.actor
          )
        )

      :error ->
        Answer.refuse(conn, :invalid_request)
    end
  end
end
