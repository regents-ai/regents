defmodule AshPlatform.AccessContext do
  @moduledoc "Auth-neutral access context for Phase 1 public shell routes."

  alias __MODULE__.AccountControl

  @enforce_keys [:principal, :capabilities]
  defstruct @enforce_keys

  def anonymous, do: %__MODULE__{principal: :anonymous, capabilities: [:view_public]}

  def account_control(%__MODULE__{principal: :anonymous}) do
    %AccountControl{kind: :sign_in, label: "Sign In"}
  end
end
