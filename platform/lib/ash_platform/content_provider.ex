defmodule AshPlatform.ContentProvider do
  @moduledoc "Public content boundary used by supervised shell work."

  @callback load(struct(), map()) :: {:ok, struct()} | {:error, term()}
end
