defmodule RegentsWeb.Techtree.RedirectController do
  @moduledoc """
  Permanent redirects from retired legacy Techtree paths under `/techtree/*` to
  their current destinations.
  """

  use RegentsWeb, :controller

  def start(conn, _params), do: moved(conn, ~p"/techtree/docs/run-locally")
  def verify(conn, _params), do: moved(conn, ~p"/techtree/docs/verify")
  def environments(conn, _params), do: moved(conn, ~p"/techtree/services/environments")
  def models(conn, _params), do: moved(conn, ~p"/techtree/services/models")
  def evals(conn, _params), do: moved(conn, ~p"/techtree/services/evals")
  def results(conn, _params), do: moved(conn, ~p"/techtree/results")
  def security(conn, _params), do: moved(conn, ~p"/techtree/services/security")

  def security_sample_report(conn, _params),
    do: moved(conn, ~p"/techtree/services/security/sample-report")

  defp moved(conn, to) do
    conn
    |> put_status(:moved_permanently)
    |> redirect(to: to)
  end
end
