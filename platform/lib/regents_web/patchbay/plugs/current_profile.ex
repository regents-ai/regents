defmodule RegentsWeb.Patchbay.Plugs.CurrentProfile do
  @moduledoc """
  Assigns `:current_profile` (a `Regents.Patchbay.Members.Member`) on Patchbay
  requests by resolving Regents' signed-in `:current_account` (or session claim).
  """

  import Plug.Conn

  alias Regents.Account.Accounts.SessionAuthority
  alias RegentsWeb.Patchbay.CurrentProfile

  def init(opts), do: opts

  def call(conn, _opts) do
    case conn.assigns[:current_account] do
      %{} = account ->
        profile = CurrentProfile.member_for_account(account)

        conn
        |> assign(:current_profile, profile)
        |> assign(:signed_out_reason, signed_out_reason(profile, false))

      nil ->
        resolve_from_session(conn)
    end
  end

  def signed_out_reason(nil, true), do: :expired
  def signed_out_reason(nil, false), do: :signed_out
  def signed_out_reason(_profile, _ended?), do: nil

  defp resolve_from_session(conn) do
    session = get_session(conn)

    case SessionAuthority.claim(session) do
      nil ->
        conn
        |> assign(:current_profile, nil)
        |> assign(:current_lineage, nil)
        |> assign(
          :signed_out_reason,
          signed_out_reason(nil, SessionAuthority.claim_shaped?(session))
        )

      claim ->
        case SessionAuthority.resolve(claim) do
          {lineage, %{} = account} ->
            profile = CurrentProfile.member_for_account(account)

            conn
            |> assign(:current_profile, profile)
            |> assign(:current_lineage, lineage)
            |> assign(:signed_out_reason, signed_out_reason(profile, false))

          _other ->
            conn
            |> assign(:current_profile, nil)
            |> assign(:current_lineage, nil)
            |> assign(:signed_out_reason, :expired)
        end
    end
  end
end
