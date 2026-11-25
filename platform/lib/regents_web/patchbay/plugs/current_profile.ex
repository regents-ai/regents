defmodule RegentsWeb.Patchbay.Plugs.CurrentProfile do
  @moduledoc """
  Assigns `:current_profile` (a `Regents.Patchbay.Members.Member`) on Patchbay
  requests using the account already resolved by the browser pipeline.
  """

  import Plug.Conn

  alias RegentsWeb.Patchbay.CurrentProfile

  def init(opts), do: opts

  def call(conn, _opts) do
    profile = CurrentProfile.member_for_account(conn.assigns[:current_human_account])

    conn
    |> assign(:current_profile, profile)
    |> assign(:signed_out_reason, signed_out_reason(profile, conn.assigns[:session_refused]))
  end

  defp signed_out_reason(nil, true), do: :expired
  defp signed_out_reason(nil, _refused), do: :signed_out
  defp signed_out_reason(_profile, _refused), do: nil
end
