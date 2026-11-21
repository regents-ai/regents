defmodule Regents.Keyfleet.Atlas.Source do
  @moduledoc """
  Where a thing the Atlas counts lives: the workspace's graph (`:graph`), whose
  things are its items, each of the kind its type names, or the fleet's
  notebook hub (`:notebook`), whose things are notebooks, of the kind
  `"notebook"`.
  """
  use Ash.Type.Enum, values: [:graph, :notebook]

  @doc "The kind every notebook is counted as; no item of the graph has it."
  def notebook_kind, do: "notebook"
end
