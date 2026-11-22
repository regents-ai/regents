defmodule RegentsWeb.Autolaunch do
  @moduledoc """
  Autolaunch's pages under `/autolaunch/...`, in one scope of the router. The
  scope marks the page `data-product="autolaunch"`, which with Autolaunch's frame
  on the page selects Autolaunch's stylesheets (`assets/css/autolaunch`), and
  every page is read under the site's bar inside Autolaunch's frame
  (`RegentsWeb.Autolaunch.Layouts`). The overview at `/autolaunch` is still the
  app's page (`RegentsWeb.RouteCatalog`) until Autolaunch's home comes in. Each
  written page also answers as Markdown at its own address
  (`RegentsWeb.Autolaunch.PublicDocuments`).
  """
  use Boundary,
    deps: [RegentsWeb, Regents.Autolaunch],
    exports: [HowItWorksLive, Layouts, PublicDocuments, PublicPagesController]
end
