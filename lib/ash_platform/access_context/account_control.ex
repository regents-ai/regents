defmodule AshPlatform.AccessContext.AccountControl do
  @moduledoc "Ash-owned shell view model for the account target."

  @enforce_keys [:kind, :label, :profile_path, :settings_path]
  defstruct @enforce_keys ++ [avatar_src: nil]
end
