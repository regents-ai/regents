defmodule Regents.SharedProfiles do
  @moduledoc """
  Saves a person's Public Display Name in their shared Regent profile through the
  profile's own actions, as the profile API does for a signed-in person of this
  site's Privy app.
  """

  def put_name!(privy_user_id, name) do
    now = System.system_time(:second)

    person = %RegentPrivy.Session{
      app_id: Application.fetch_env!(:regents, :privy)[:app_id],
      privy_user_id: privy_user_id,
      session_id: "shared-profile",
      wallet_addresses: [],
      issued_at: now - 1,
      expires_at: now + 600
    }

    {:ok, profile} = RegentIdentity.sync(person)

    RegentIdentity.edit_profile!(profile, %{display_name: name},
      actor: RegentIdentity.Owner.of(person)
    )
  end
end
