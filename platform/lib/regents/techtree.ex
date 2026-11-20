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
      Catalog.Route,
      ModelClimb,
      Release,
      Train.Comparisons
    ]

  alias Regents.Techtree.Catalog.Query

  @doc """
  `:ok` while a catalog release is active on the configured channel, else the
  catalog's error: one read, bounded by `Regents.Products.health/0`.
  """
  def health do
    with {:ok, _release} <- Query.active_catalog_release(), do: :ok
  end
end
