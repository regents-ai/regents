defmodule RegentsWeb.Plugs.ProfileOwner do
  @moduledoc """
  Puts the profile's owner on a profile API request (`RegentIdentity.HTTP`): the
  person signed in on this site, or the person a paired agent acts for, decided
  by `RegentsWeb.Plugs.PersonOrAgent`. A signed-out request gets no owner, and
  the profile API refuses it with `authentication_required`.
  """

  @behaviour Plug

  alias Regents.Actors.{Agent, Human}
  alias RegentsWeb.Plugs.PersonOrAgent

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case PersonOrAgent.call(conn, []) do
      %{halted: true} = conn -> conn
      %{assigns: %{actor: %Human{}}} = conn -> owner(conn, conn.assigns.current_human_account)
      %{assigns: %{actor: %Agent{} = agent}} = conn -> owner(conn, agent)
      %{assigns: %{actor: nil}} = conn -> conn
    end
  end

  defp owner(conn, %{privy_user_id: privy_user_id}) do
    app_id = :regents |> Application.fetch_env!(:privy) |> Keyword.fetch!(:app_id)

    RegentIdentity.HTTP.put_owner(conn, %RegentIdentity.Owner{
      app_id: app_id,
      privy_user_id: privy_user_id
    })
  end
end
