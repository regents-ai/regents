defmodule RegentsWeb.Techtree do
  @moduledoc """
  Techtree's pages, all under `/techtree` in one scope of the router with their
  own live session. The scope marks the page `data-brand="techtree"`, which
  selects Techtree's palette and its stylesheets (`assets/css/techtree`), and
  each page is read inside Techtree's own header and footer
  (`RegentsWeb.Techtree.Layouts`). Its API is under `/api/v1/techtree`; its
  agent guide, `/techtree/agents.md`, the Skill comparisons,
  `/techtree/train.json` and each comparison's report, and each published
  Result's share picture, `/techtree/results/:bundle_digest/share.png`, are
  answered outside the page scope.
  """
  use Boundary,
    deps: [RegentsWeb, Regents.Techtree],
    exports: [
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
      PublicationController,
      PublicDocuments,
      PublicPagesController,
      PublishedSkillController,
      ResultShareCardController,
      RunsLive.Index,
      RunsLive.Show,
      ServiceLive,
      TddShowcaseLive,
      TrainController,
      TrainLive.Show
    ]
end
