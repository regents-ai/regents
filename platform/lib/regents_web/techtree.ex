defmodule RegentsWeb.Techtree do
  @moduledoc """
  Techtree's pages, all under `/techtree` in one scope of the router with their
  own live session. The scope marks the page `data-brand="techtree"`, which
  selects Techtree's palette and its stylesheets (`assets/css/techtree`), and
  each page is read inside Techtree's own header and footer
  (`RegentsWeb.Techtree.Layouts`). Its API is under `/api/v1/techtree`.
  """
  use Boundary,
    deps: [RegentsWeb, Regents.Techtree],
    exports: [
      BootstrapController,
      CatalogController,
      ChangelogLive,
      ClimbController,
      FormalLive,
      HomeLive,
      Layouts,
      ModelClimbReportController,
      ObjectController,
      PublicPagesController,
      ServiceLive,
      TrainLive.Show
    ]
end
