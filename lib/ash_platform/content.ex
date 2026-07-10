defmodule AshPlatform.Content do
  @moduledoc "Bounded public fixture content rendered by the Phase 1 shell."

  @enforce_keys [:eyebrow, :status, :title, :summary, :details]
  defstruct @enforce_keys
end
