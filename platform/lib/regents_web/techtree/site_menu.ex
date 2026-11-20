defmodule RegentsWeb.Techtree.SiteMenu do
  @moduledoc """
  The site's pages for the bar and the footer (`RegentsWeb.Techtree.Layouts`).

  The bar links Results and Docs, after Services. The footer lists the services
  (`RegentsWeb.Techtree.Services`), Techtree's Results, Docs, changelog and code on
  GitHub with the site's own pages, and the files to hand an agent, in columns, by
  name.
  """

  use RegentsWeb, :verified_routes

  alias RegentsWeb.Techtree.Services

  @repository "https://github.com/regents-ai/techtree"
  @buy_regent "https://app.uniswap.org/explore/tokens/base/0x6f89bcA4eA5931EdFCB09786267b251DeE752b07"

  @type link :: %{name: String.t(), href: String.t()}
  @type column(entry) :: %{id: String.t(), title: String.t(), pages: [entry]}

  @doc "The bar's links after Services, by name and address."
  @spec links() :: [link()]
  def links, do: [link("Results", ~p"/techtree/results"), link("Docs", ~p"/techtree/docs")]

  @doc "The footer's columns, each page by name and address."
  @spec footer() :: [column(link())]
  def footer do
    [
      column(
        "services",
        "Services",
        for(
          service <- Services.all() ++ Services.others(),
          do: link(service.name, Services.path(service.id))
        )
      ),
      column("site", "Site", [
        link("Results", ~p"/techtree/results"),
        link("Docs", ~p"/techtree/docs"),
        link("Run locally", ~p"/techtree/docs/run-locally"),
        link("Changelog", ~p"/techtree/changelog"),
        link("GitHub", @repository),
        link("About", ~p"/about"),
        link("Buy $REGENT", @buy_regent)
      ]),
      column("agents", "Agents", [
        link("Agents", ~p"/agents"),
        link("agents.md", ~p"/agents.md"),
        link("llms.txt", ~p"/llms.txt"),
        link("capabilities.json", ~p"/capabilities.json"),
        link("openapi.json", ~p"/openapi.json"),
        link("Public API", ~p"/techtree/docs/api"),
        link("Browser agents", ~p"/techtree/docs/browser-agents")
      ])
    ]
  end

  defp column(id, title, pages), do: %{id: id, title: title, pages: pages}

  defp link(name, href), do: %{name: name, href: href}
end
