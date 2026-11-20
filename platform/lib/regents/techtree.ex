defmodule Regents.Techtree do
  @moduledoc """
  Techtree's core: custom Skills, evaluations, training environments and
  open-weight models, folded in from techtree.sh one slice at a time
  (`SOURCE.json` beside this module names what came from where). Its tables
  stay in Techtree's own schema, `techtree_app`, with their own migrations and
  ledger (`priv/techtree`); so far Model Climb's reports
  (`Regents.Techtree.ModelClimb`) and the catalog's releases and entries
  (`Regents.Techtree.Catalog`, whose bundle is `priv/techtree/catalog`). The
  published Skill comparisons are committed files
  (`Regents.Techtree.Train.Comparisons`). Its pages are `RegentsWeb.Techtree`, and
  its release commands `Regents.Techtree.Release`.
  """
  use Boundary,
    top_level?: true,
    deps: [Regents],
    exports: [
      Catalog.Bundle,
      Catalog.Digest,
      Catalog.Error,
      Catalog.Query,
      ModelClimb,
      Release,
      Train.Comparisons
    ]

  @doc "Always `:ok`: Techtree has no facts of its own on this site yet (`Regents.Products.health/0`)."
  def health, do: :ok
end
