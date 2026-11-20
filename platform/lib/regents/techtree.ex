defmodule Regents.Techtree do
  @moduledoc """
  Techtree's core: custom Skills, evaluations, training environments and
  open-weight models, folded in from techtree.sh one slice at a time
  (`SOURCE.json` beside this module names what came from where). It keeps no
  table yet: the published Skill comparisons are committed files
  (`Regents.Techtree.Train.Comparisons`). Its pages are `RegentsWeb.Techtree`.
  """
  use Boundary, top_level?: true, exports: [Train.Comparisons]

  @doc "Always `:ok`: Techtree has no facts of its own on this site yet. Not used yet."
  def health, do: :ok
end
