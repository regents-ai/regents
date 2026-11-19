defmodule Regents.AgentAccount do
  @moduledoc """
  How the shared agent requests (`RegentAgents.HTTP`) name the person an agent is
  paired with: an agent's check-in (`GET /api/agents/v1/me`) names their account
  as the person's own Account page names it, and the SIWA service's pairing read
  (`POST /api/agents/v1/pairing`) names them by their profile code.
  """

  alias Regents.Accounts
  alias Regents.Actors.System

  # Nil until the person first signs in here; the check-in is then refused.
  @spec account(String.t()) :: %{display_name: String.t() | nil, ens_name: String.t() | nil} | nil
  def account(privy_user_id) do
    case Accounts.get_by_privy_did(privy_user_id,
           actor: %System{},
           load: [:display_name, :ens_name]
         ) do
      {:ok, %{} = account} -> %{display_name: account.display_name, ens_name: account.ens_name}
      {:ok, nil} -> nil
    end
  end

  @doc """
  The person's profile code: the ID of their shared Regent profile
  (`RegentIdentity.profile_id/2`), which a hello card names as its `person`. Nil
  until they have a profile, which their first sign-in with a wallet makes; the
  pairing read then answers `person_has_no_profile`. A profile that can't be read
  raises, so the SIWA service hears the site failed, never that the agent is not
  paired.
  """
  @spec person(String.t()) :: String.t() | nil
  def person(privy_user_id) do
    app_id = :regents |> Application.fetch_env!(:privy) |> Keyword.fetch!(:app_id)

    # The raise names no one: the error it replaces can carry the person's sign-in ID.
    case RegentIdentity.profile_id(app_id, privy_user_id) do
      {:ok, profile_id} -> profile_id
      {:error, _error} -> raise "a paired person's profile could not be read"
    end
  end
end
