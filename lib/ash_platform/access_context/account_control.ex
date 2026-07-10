defmodule AshPlatform.AccessContext.AccountControl do
  @moduledoc "Ash-owned shell view model for the account target."

  @enforce_keys [:kind, :label]
  defstruct @enforce_keys
end
