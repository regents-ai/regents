defmodule RegentsWeb.AgentReadsController do
  @moduledoc "Private reads for a distinct, currently paired SIWA agent."
  use RegentsWeb, :controller

  alias RegentPoints.Rules
  alias Regents.Points.Board
  alias Regents.SharedReading
  alias RegentsWeb.PointsEntries

  @points_off "Earning Points is off on this site."

  def account(conn, _params) do
    actor = conn.assigns.actor

    case Regents.Accounts.get_human_account(actor.human_account_id, actor: actor) do
      {:ok, account} ->
        json(conn, %{
          account: Map.take(account, [:id, :display_name, :ens_name]),
          pairing_id: actor.pairing_id,
          agent_wallet: actor.wallet_address
        })

      {:error, _} ->
        unavailable(conn)
    end
  end

  # Points as decimal text, the same figures the Points page shows. While the
  # page would show the board as not read, the whole answer is unavailable.
  def points(conn, _params) do
    actor = conn.assigns.actor

    with {:ok, summary} <- RegentPoints.summary(actor: actor),
         {:ok, %{reading: %{} = board}} <- SharedReading.fetch(Board.key()) do
      earning = Rules.active()
      answer = PointsEntries.answer(summary, board, actor.human_account_id, earning != [])
      json(conn, with_note(answer, points_note(earning)))
    else
      _not_read -> unavailable(conn)
    end
  end

  defp points_note([]), do: @points_off
  defp points_note(_earning), do: nil

  defp with_note(answer, nil), do: answer
  defp with_note(answer, note), do: Map.put(answer, :note, note)

  defp unavailable(conn),
    do:
      conn
      |> put_status(503)
      |> json(%{
        error: %{
          code: "unavailable",
          message: "That could not be reached right now.",
          hint: "Try again in a moment."
        }
      })
end
