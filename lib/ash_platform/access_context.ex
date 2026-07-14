defmodule AshPlatform.AccessContext do
  @moduledoc "Principal-aware access context for public shell routes."

  alias __MODULE__.AccountControl
  alias AshPlatform.PublicIdentity

  @enforce_keys [:principal, :capabilities]
  defstruct @enforce_keys

  def anonymous, do: %__MODULE__{principal: :anonymous, capabilities: [:view_public]}

  def human(account), do: %__MODULE__{principal: {:human, account}, capabilities: [:view_public]}

  def account_control(access_context, regent \\ nil)

  def account_control(%__MODULE__{principal: :anonymous}, _regent) do
    %AccountControl{
      kind: :sign_in,
      label: "Sign In",
      profile_path: nil,
      settings_path: nil
    }
  end

  def account_control(%__MODULE__{principal: {:human, account}}, %{
        slug: slug,
        display_name: name
      }) do
    %AccountControl{
      kind: :signed_in,
      label: name,
      profile_path: "/regents/#{slug}",
      settings_path: "/settings",
      avatar_data_uri: PublicIdentity.avatar_data_uri(account)
    }
  end

  def account_control(%__MODULE__{principal: {:human, account}}, _regent) do
    %AccountControl{
      kind: :signed_in,
      label: PublicIdentity.label(account),
      profile_path: nil,
      settings_path: "/settings",
      avatar_data_uri: PublicIdentity.avatar_data_uri(account)
    }
  end
end
