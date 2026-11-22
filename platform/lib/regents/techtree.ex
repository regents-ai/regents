defmodule Regents.Techtree do
  @moduledoc """
  Techtree's core: custom Skills, evaluations, training environments and
  open-weight models, folded in from techtree.sh one slice at a time
  (`SOURCE.json` beside this module names what came from where). Its tables
  stay in Techtree's own schema, `techtree_app`, with their own migrations and
  ledger (`priv/techtree`); so far Model Climb's reports
  (`Regents.Techtree.ModelClimb`), the catalog's releases and entries
  (`Regents.Techtree.Catalog`, whose bundle is `priv/techtree/catalog`), the
  public run log of published Results (`Regents.Techtree.Network`, read only
  here: nothing publishes to it yet), the Wallet Bench's tests
  (`Regents.Techtree.WalletBench`, read only here: techtree.sh runs them) and
  the projects Techtree's team delivered to customers
  (`Regents.Techtree.Projects`, read only here: techtree.sh's team delivers
  them). The
  published Skill comparisons are committed files
  (`Regents.Techtree.Train.Comparisons`), and so are the starter Skills
  (`Regents.Techtree.Release.StarterSkill`, `priv/techtree/release`). Its pages
  are `RegentsWeb.Techtree`, and
  its release commands `Regents.Techtree.Release`.
  """
  use Boundary,
    top_level?: true,
    deps: [Regents],
    exports: [
      Canonical,
      Catalog.Bundle,
      Catalog.Digest,
      Catalog.Error,
      Catalog.Query,
      Catalog.Route,
      Enquiries,
      Enquiries.Enquiry,
      ModelClimb,
      ModelClimb.Proof,
      Network,
      Network.AgentVersions,
      Network.Assessment,
      Network.Document,
      Network.Error,
      Network.Ingest,
      Network.Key,
      Network.Projection,
      Network.Query,
      Network.ResultFilters,
      Network.Verdict,
      Projects,
      Release,
      Release.StarterSkill,
      Train.Comparisons,
      WalletBench,
      WalletBench.BaseRpc,
      WalletBench.Catalog,
      WalletBench.Evidence,
      WalletBench.Judge,
      WalletBench.Reading,
      Watchdog,
      Watchdog.Host,
      Watchdog.Limits,
      Watchdog.Ownership,
      Watchdog.Route
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
