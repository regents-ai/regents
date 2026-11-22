defmodule RegentsWeb.Techtree.SiteMenu do
  @moduledoc """
  The site's pages for Techtree's row and the footer (`RegentsWeb.Techtree.Layouts`).

  The row has one menu, Services: the four services (`RegentsWeb.Techtree.Services`)
  with Security and Swarm Verify set apart beside them, each with a Lucide icon and
  one short line. Results and Docs are plain links beside it. The footer lists the services
  (`RegentsWeb.Techtree.Services`), Techtree's Results, Docs, changelog, the site's
  blog, code on GitHub and About with the site's own pages, and the files to hand an
  agent, Techtree's agents' pages and agent guide first, in columns, by name.
  """

  use RegentsWeb, :verified_routes

  alias RegentsWeb.Techtree.Services

  @repository "https://github.com/regents-ai/techtree"
  @buy_regent "https://app.uniswap.org/explore/tokens/base/0x6f89bcA4eA5931EdFCB09786267b251DeE752b07"

  @type page :: %{name: String.t(), icon: String.t(), line: String.t(), href: String.t()}
  @type link :: %{name: String.t(), href: String.t()}
  @type column(entry) :: %{id: String.t(), title: String.t(), pages: [entry]}

  @doc "The Services menu: the four services, then Security and Swarm Verify on their own."
  @spec services() :: [column(page())]
  def services do
    [
      column("services", "Services", Enum.map(Services.all(), &service/1)),
      column("also", "Also", Enum.map(Services.others(), &service/1))
    ]
  end

  @doc "The row's links after Services, by name and address."
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
        link("Blog", ~p"/articles"),
        link("GitHub", @repository),
        link("About", ~p"/techtree/about"),
        link("Buy $REGENT", @buy_regent)
      ]),
      column("agents", "Agents", [
        link("Agents", ~p"/techtree/agents"),
        link("agents.md", ~p"/techtree/agents.md"),
        link("llms.txt", ~p"/llms.txt"),
        link("capabilities.json", ~p"/capabilities.json"),
        link("openapi.json", ~p"/openapi.json"),
        link("Public API", ~p"/techtree/docs/api"),
        link("Browser agents", ~p"/techtree/docs/browser-agents")
      ])
    ]
  end

  defp service(service),
    do: %{
      name: service.name,
      icon: service.icon,
      line: service.line,
      href: Services.path(service.id)
    }

  defp column(id, title, pages), do: %{id: id, title: title, pages: pages}

  defp link(name, href), do: %{name: name, href: href}
end
