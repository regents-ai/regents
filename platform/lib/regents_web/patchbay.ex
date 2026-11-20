defmodule RegentsWeb.Patchbay do
  @moduledoc """
  Patchbay's pages under `/patchbay/...`, in one scope of the router. The scope
  marks the page `data-product="patchbay"`, which with Patchbay's frame on the
  page selects Patchbay's stylesheets (`assets/css/patchbay`), and every page is
  read under the site's bar inside Patchbay's frame (`RegentsWeb.Patchbay.Layouts`).
  The overview at `/patchbay` is still the app's page (`RegentsWeb.RouteCatalog`)
  until Patchbay's home comes in. Each page also answers as Markdown at its own
  address (`RegentsWeb.Patchbay.PublicDocuments`).
  """
  use Boundary,
    deps: [RegentsWeb, Regents.Patchbay],
    exports: [
      BlogController,
      Forum.BoardController,
      Forum.TroubleshootingPages,
      Layouts,
      PagesController,
      PublicDocuments
    ]
end
