defmodule Regents.Techtree do
  @moduledoc """
  Techtree's core: custom Skills, evaluations, training environments, and
  open-weight models, consolidated under `/techtree` (`SOURCE.json` beside this
  module records provenance). Its tables live in `techtree_app` with their own
  migrations (`priv/techtree`): Model Climb proofs (`Regents.Techtree.ModelClimb`),
  catalog releases and entries (`Regents.Techtree.Catalog`, bundled in
  `priv/techtree/catalog`), the public run log of published Results and signed
  publication/withdrawal ingest (`Regents.Techtree.Network`), the Agent Wallet
  Bench (`Regents.Techtree.WalletBench`), delivered customer Projects
  (`Regents.Techtree.Projects`), contact-form Enquiries
  (`Regents.Techtree.Enquiries`), and Watchdog site ownership monitoring
  (`Regents.Techtree.Watchdog`). Published Skill comparisons are committed files
  (`Regents.Techtree.Train.Comparisons`), and starter Skills live in
  `Regents.Techtree.Release.StarterSkill` (`priv/techtree/release`). Its web
  surface is `RegentsWeb.Techtree`, its core supervisor is
  `Regents.Techtree.Supervisor`, and its release commands are
  `Regents.Techtree.Release`.
  """
  use Boundary,
    top_level?: true,
    deps: [Regents],
    exports: [
      Canonical,
      Capabilities,
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
      Supervisor,
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
