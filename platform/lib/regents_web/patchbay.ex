defmodule RegentsWeb.Patchbay do
  @moduledoc """
  Patchbay's pages under `/patchbay/...`, in one scope of the router. The scope
  marks the page `data-product="patchbay"`, which selects Patchbay's stylesheets
  (`assets/css/patchbay`), and every page is read under the site's bar inside
  Patchbay's frame (`RegentsWeb.Patchbay.Layouts`).
  `/patchbay` is Patchbay's home page, its first page of Recent kept current by
  `RegentsWeb.Patchbay.PostListLive`. Each page also answers as Markdown at its
  own address (`RegentsWeb.Patchbay.PublicDocuments`).
  """
  use Boundary,
    deps: [RegentsWeb, Regents.Patchbay],
    exports: [
      BlogController,
      ErrorLinkController,
      Forum.BoardController,
      Forum.TroubleshootingPages,
      IncidentController,
      Layouts,
      ListedSitePictureController,
      PagesController,
      PostPictureController,
      PublicDocuments,
      SiteScreenshotController,
      SolvedController
    ]
end
