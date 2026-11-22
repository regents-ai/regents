defmodule Regents.Patchbay.OAuth do
  @moduledoc """
  Patchbay's bridge to `RegentOAuth` for MCP event subscriptions and
  disconnecting a suspended member's connected apps.
  """

  alias Regents.Patchbay.Members
  alias Regents.Patchbay.Members.Member

  @doc "The active Patchbay member for OAuth subject `privy_user_id`, or nil."
  @spec profile(String.t()) :: Member.t() | nil
  def profile(privy_user_id) when is_binary(privy_user_id) do
    case Members.get_profile_by_privy_user_id(privy_user_id) do
      {:ok, %Member{} = member} ->
        if Member.may_act?(member), do: member, else: nil

      _other ->
        nil
    end
  end

  def profile(_other), do: nil

  @doc "Revokes every connected OAuth app belonging to a suspended member."
  @spec disconnect_apps(Member.t()) :: :ok
  def disconnect_apps(%Member{authentication_origin: :privy, privy_user_id: subject})
      when is_binary(subject) do
    subject
    |> RegentOAuth.connected_clients()
    |> Enum.each(fn %{id: client_id} ->
      {:ok, :ok} = RegentOAuth.revoke_client(subject, client_id)
    end)

    :ok
  end

  def disconnect_apps(_member), do: :ok
end
