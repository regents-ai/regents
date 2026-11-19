defmodule Regents.Cloak do
  @moduledoc """
  Cloak's core. Cloak keeps nothing on this site yet: its page is
  `RegentsWeb.Cloak`.
  """
  use Boundary, top_level?: true

  @doc "Always `:ok`: Cloak has no facts of its own on this site yet. Not used yet."
  def health, do: :ok
end
