defmodule RegentsWeb.Keyfleet.NotebookOpenController do
  # How soon someone sent to a fleet's notebooks who is back already is taken to
  # be in a browser that didn't keep the notebook sign-in.
  @again_within 30

  @moduledoc """
  Opens a fleet's notebooks for the person signed in here, landing on `to`:
  the notebooks' start page, one notebook or a saved output
  (`Regents.Keyfleet.Notebooks.destination?/1`). A holder's browser is handed a
  page that sends a code that works once to the fleet's notebook host
  (`RegentsWeb.Keyfleet.NotebookOpenHTML`), by itself unless this site sent the same
  person to the same fleet's notebooks in the last #{@again_within} seconds; then
  it waits for a press, so a browser that won't keep the notebook sign-in isn't
  sent round and round. A saved output's address sends someone without a
  notebook sign-in here (`RegentsWeb.Keyfleet.Plugs.NotebookGateway`); a holder of one
  of the fleet's keys goes back to it the same way, and anyone else lands on
  the fleet's workspace with a note saying why.
  Key ownership that can't be read, other than while it is being brought up
  to date, is saved with the site's errors (`Regents.Keyfleet.Notebooks.RecordsDownError`).
  """
  use RegentsWeb, :controller

  alias Regents.Account.Actors.Human
  alias Regents.Keyfleet.{Fleets, Notebooks}
  alias Regents.Keyfleet.Keys.Errors.OwnershipRefreshingError
  alias Regents.Keyfleet.Notebooks.RecordsDownError
  alias RegentsWeb.ContentSecurityPolicy

  def open(conn, %{"fleet_id" => fleet_id} = params) do
    case open_for(conn, fleet_id, params["to"]) do
      {:ok, entry} ->
        nonce = 18 |> :crypto.strong_rand_bytes() |> Base.encode64()
        notebooks = URI.to_string(%{URI.parse(entry.action) | path: nil})
        by_itself? = not sent_lately?(conn, fleet_id)

        # The site's referrer policy stays: under `no-referrer` a browser sends
        # the form with the origin `null`, which the notebook host refuses.
        conn
        |> put_resp_header("cache-control", "no-store")
        |> put_resp_header(
          "content-security-policy",
          ContentSecurityPolicy.notebook_entry(nonce, notebooks)
        )
        |> sent(fleet_id, by_itself?)
        |> put_root_layout(false)
        |> put_view(html: RegentsWeb.Keyfleet.NotebookOpenHTML)
        |> render(:entry,
          entry: entry,
          nonce: nonce,
          by_itself?: by_itself?,
          fleet_name: Fleets.name(fleet_id),
          workspace_path: Fleets.path(fleet_id) <> "/workspace"
        )

      {:error, :no_hub} ->
        conn
        |> put_flash(:error, "This fleet has no notebooks yet.")
        |> redirect(to: "/keyfleet/app")

      {:error, reason} when is_atom(reason) or is_struct(reason, OwnershipRefreshingError) ->
        to_workspace(conn, fleet_id, reason)

      {:error, error} ->
        RecordsDownError.report(
          "Key ownership in #{fleet_id} could not be read to open its notebooks: " <>
            inspect(error.__struct__)
        )

        to_workspace(conn, fleet_id, error)
    end
  end

  defp sent_lately?(conn, fleet_id) do
    case get_session(conn, :notebooks_sent) do
      {^fleet_id, at} -> System.system_time(:second) - at < @again_within
      _other -> false
    end
  end

  defp sent(conn, fleet_id, true),
    do: put_session(conn, :notebooks_sent, {fleet_id, System.system_time(:second)})

  defp sent(conn, _fleet_id, false), do: conn

  defp to_workspace(conn, fleet_id, reason) do
    conn
    |> put_flash(:error, notice(reason))
    |> redirect(to: Fleets.path(fleet_id) <> "/workspace")
  end

  defp open_for(%Plug.Conn{assigns: %{current_human_account: nil}}, fleet_id, _to),
    do: if(Notebooks.hub?(fleet_id), do: {:error, :signed_out}, else: {:error, :no_hub})

  defp open_for(conn, fleet_id, to) do
    Notebooks.open(
      Human.for_account(conn.assigns.current_human_account),
      conn.assigns.current_lineage,
      fleet_id,
      to
    )
  end

  defp notice(:signed_out), do: "Sign in to open this fleet’s notebooks."
  defp notice(:not_holder), do: "Only holders of this fleet’s Keys can open its notebooks."
  defp notice(:invalid_destination), do: "That notebook link isn’t complete. Ask for it again."
  defp notice(_error), do: "The notebooks can’t be opened right now. Try again in a minute."
end
