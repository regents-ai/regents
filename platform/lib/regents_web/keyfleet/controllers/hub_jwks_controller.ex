defmodule RegentsWeb.Keyfleet.HubJwksController do
  @moduledoc """
  The public keys the fleets' notebook hubs check this site's passes with
  (`Regents.Keyfleet.Notebooks.Pass`), open while the rest of the site is closed.
  """
  use RegentsWeb, :controller

  def show(conn, _params) do
    conn
    |> put_resp_header("cache-control", "public, max-age=300")
    |> json(Regents.Keyfleet.Notebooks.Pass.jwks())
  end
end
