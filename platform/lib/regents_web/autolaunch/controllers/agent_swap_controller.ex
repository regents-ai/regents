defmodule RegentsWeb.Autolaunch.AgentSwapController do
  @moduledoc """
  Swaps on a launched token for a signed, paired agent, acting for the person
  it is paired with: the steps of one buy or sell of a token the site lists,
  named by its id as `autolaunch_tokens` lists it. The verified request names
  the agent and so the account (`RegentsWeb.Account.PairedAgent`); a signer
  named in the body is used only when it is one of that account's own wallets,
  and with none named the account's signed-in wallet is used. The site only
  prepares the steps: the wallet's own key signs and sends them
  (`Regents.Autolaunch.AgentSwap`).
  """

  use RegentsWeb, :controller

  alias RegentsWeb.Autolaunch.AgentSwapAnswer, as: Answer

  def prepare(conn, %{"token_id" => token_id}) do
    case Answer.input(conn.body_params) do
      {:ok, input} ->
        Answer.send(
          conn,
          Regents.Autolaunch.prepare_swap(Map.put(input, "token_id", token_id),
            actor: conn.assigns.actor
          )
        )

      :error ->
        Answer.refuse(conn, :invalid_request)
    end
  end
end
