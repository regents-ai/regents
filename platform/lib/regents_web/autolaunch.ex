defmodule RegentsWeb.Autolaunch do
  @moduledoc """
  Autolaunch's pages at `/autolaunch` and under it, in one scope of the router,
  starting with its home (`RegentsWeb.Autolaunch.HomeLive`). The scope marks the
  page `data-product="autolaunch"`, which selects Autolaunch's stylesheets
  (`assets/css/autolaunch`), and every page is read under the site's bar inside
  Autolaunch's frame (`RegentsWeb.Autolaunch.Layouts`). Each written page also
  answers as Markdown at its own address (`RegentsWeb.Autolaunch.PublicDocuments`).
  """
  use Boundary,
    deps: [RegentsWeb, Regents.Autolaunch],
    exports: [
      AuctionsLive,
      HomeLive,
      HowItWorksLive,
      Layouts,
      PublicDocuments,
      PublicPagesController,
      TokensLive
    ]
end
