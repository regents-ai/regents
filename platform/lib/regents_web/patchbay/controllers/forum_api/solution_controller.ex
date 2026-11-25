defmodule RegentsWeb.Patchbay.ForumAPI.SolutionController do
  @moduledoc """
  The one endpoint behind accepting an answer: the asker of a paid priority
  report names the reply that settled it, and the money held for the report
  goes to that reply's author.

  Nothing a caller sends names the asker; the identity comes from the profile
  signed in on the session. `Regents.Patchbay.Forum.SolutionAccept` queues the
  payout and the response reports the current escrow state.
  """

  use RegentsWeb, :controller

  alias Regents.Patchbay.Forum.SolutionAccept
  alias RegentsWeb.Patchbay.ApiError
  alias RegentsWeb.Patchbay.AuthorJSON
  alias RegentsWeb.Patchbay.ForumAPI.Refusal

  def create(conn, %{"id" => id} = params) do
    case SolutionAccept.run(id, params["reply_id"], conn.assigns.current_profile) do
      {:ok, accepted} ->
        json(conn, %{
          accepted: true,
          report_id: accepted.id,
          reply_id: accepted.accepted_reply_id,
          escrow_status: accepted.escrow_status,
          release_tx_hash: accepted.escrow_release_tx_hash,
          winner: AuthorJSON.author(accepted.accepted_reply.author)
        })

      {:error, failure} ->
        send_failure(conn, failure)
    end
  end

  defp send_failure(conn, :not_found) do
    conn
    |> put_status(:not_found)
    |> json(
      ApiError.body(
        "not_found",
        "There is no thread with that id.",
        "Search with regents patchbay threads search --query WORDS (or the search_threads tool)."
      )
    )
  end

  defp send_failure(conn, %Ash.Error.Forbidden{}) do
    conn
    |> put_status(:forbidden)
    |> json(
      ApiError.body(
        "forbidden",
        "Only the asker of this report can accept an answer to it.",
        "Sign in as the report's asker to accept it."
      )
    )
  end

  defp send_failure(conn, error) do
    if SolutionAccept.missing?(error) do
      send_failure(conn, :not_found)
    else
      conn
      |> put_status(:unprocessable_entity)
      |> json(ApiError.invalid(Refusal.messages(error)))
    end
  end
end
