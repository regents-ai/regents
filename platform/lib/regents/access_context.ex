defmodule Regents.AccessContext do
  @moduledoc "Principal-aware access context for public shell routes."

  alias __MODULE__.AccountControl
  alias Regents.PublicIdentity

  @enforce_keys [:principal, :capabilities]
  defstruct @enforce_keys

  def anonymous, do: %__MODULE__{principal: :anonymous, capabilities: [:view_public]}

  def human(account), do: %__MODULE__{principal: {:human, account}, capabilities: [:view_public]}

  def account_control(access_context, regent \\ nil)

  def account_control(%__MODULE__{principal: :anonymous}, _regent) do
    %AccountControl{kind: :sign_in, label: "Sign in", profile_path: nil}
  end

  def account_control(%__MODULE__{principal: {:human, account}}, %{
        slug: slug,
        display_name: name
      }) do
    %AccountControl{
      kind: :signed_in,
      label: name,
      profile_path: "/regents/#{slug}",
      avatar_src: PublicIdentity.avatar_src(account),
      wallet: own_wallet(account)
    }
  end

  def account_control(%__MODULE__{principal: {:human, account}}, _regent) do
    %AccountControl{
      kind: :signed_in,
      label: PublicIdentity.label(account),
      profile_path: nil,
      avatar_src: PublicIdentity.avatar_src(account),
      wallet: own_wallet(account)
    }
  end

  defp own_wallet(%{wallet_address: address}) when is_binary(address),
    do: String.downcase(address)

  defp own_wallet(_account), do: nil
end
