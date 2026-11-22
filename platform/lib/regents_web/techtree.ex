defmodule RegentsWeb.Techtree do
  @moduledoc """
  Techtree's pages, all under `/techtree` in one scope of the router with their
  own live session. The scope marks the page `data-brand="techtree"`, which
  selects Techtree's palette and its stylesheets (`assets/css/techtree`), and
  each page is read under the site's bar, above Techtree's own footer
  (`RegentsWeb.Techtree.Layouts`). Its API is under `/api/v1/techtree`; its
  agent guide, `/techtree/agents.md`, the Techtree skill, `/techtree/skill.md`,
  and each agent's own, `/techtree/agents/:agent/skill.md`, the Skill comparisons,
  `/techtree/train.json` and each comparison's report, each published
  Result's share picture, `/techtree/results/:bundle_digest/share.png`, and the
  Wallet Bench's `/techtree/wallet-bench.md`, `/techtree/wallet-bench.json` and
  each test's `results.json` are answered outside the page scope. A signed-in
  person's Projects are at `/techtree/account/projects`, and their paired
  agent's reads of them under `/api/v1/techtree/account`.
  """
  use Boundary,
    deps: [RegentsWeb, Regents.Techtree],
    exports: [
      AgentAccountController,
      AgentsController,
      BootstrapController,
      CatalogController,
      ChangelogLive,
      ClimbController,
      ClimbsLive.Show,
      DocsLive,
      FormalLive,
      HomeLive,
      Layouts,
      ModelClimbReportController,
      ObjectController,
      ProjectPackageController,
      ProjectsLive,
      PublicationController,
      PublicationKeyController,
      PublicationRate,
      PublicDocuments,
      PublicPagesController,
      PublishedSkillController,
      ResultShareCardController,
      RunsLive.Index,
      RunsLive.Show,
      ServiceLive,
      TddShowcaseLive,
      TrainController,
      TrainLive.Show,
      WalletBenchController,
      WalletBenchEvidenceController,
      WalletBenchLive.Index,
      WalletBenchLive.Show,
      WatchdogLive
    ]
end
