defmodule RegentsWeb.Plugs.PersonOrAgent do
  @moduledoc """
  Who calls an API that a person uses with their own sign-in on this site, and an
  agent they paired uses for them. An agent's signed request acts as its person
  (`RegentsWeb.Plugs.PairedAgent`), which refuses it when it acts for no one. Any
  other request is the person's session cookie, whose request that changes
  something carries the session's forms token in x-csrf-token, as the site's
  pages send it; one without it counts as signed out, so another site's page can
  never act with the person's cookie.

  Assigns `:actor`: the signed-in `Regents.Actors.Human`, the paired
  `Regents.Actors.Agent`, or nil for a signed-out request, which the API behind
  it refuses in its own words.
  """

  @behaviour Plug

  import Plug.Conn

  alias Regents.Actors.Human
  alias RegentsWeb.Plugs.PairedAgent
  alias RegentsWeb.PrivySessionController

  @forms_token Plug.CSRFProtection.init(with: :clear_session)

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    if Siwa.AgentAuthPlug.signed_request?(conn),
      do: PairedAgent.call(conn, []),
      else: person(conn)
  end

  # The person's own sign-in on this site: the session cookie its pages hold.
  defp person(conn) do
    conn =
      conn
      |> fetch_session()
      |> Plug.CSRFProtection.call(@forms_token)
      |> PrivySessionController.enforce_authority()

    case conn.assigns.current_human_account do
      %{id: id} -> assign(conn, :actor, %Human{human_account_id: id})
      nil -> assign(conn, :actor, nil)
    end
  end
end
