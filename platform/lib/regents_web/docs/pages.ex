defmodule RegentsWeb.Docs.Pages do
  @moduledoc """
  The docs pages, one per topic under `/docs`, in five sections. Each page's
  words live in `priv/public/docs/<key>.md`. The router and the sitemap read the
  addresses while compiling, so this module depends on nothing else in the site.
  """

  # Each section's pages in reading order; the first page of a section is where
  # its tab leads. `nil` is the overview at /docs itself.
  @sections [
    {"Start", [{nil, "Overview"}, {"limits", "Limits"}, {"errors", "Errors"}]},
    {"API", [{"products", "Products"}, {"reading", "Reading"}, {"profiles", "Profiles"}]},
    {"Agents", [{"pairing", "Pairing"}, {"agent-reads", "Signed reads"}, {"webmcp", "WebMCP"}]},
    {"Account", [{"claims", "Claims"}, {"staking", "Staking"}]},
    {"Reference", [{"contracts", "Contracts"}, {"changes", "Changes"}]}
  ]

  @directory Application.app_dir(:regents, "priv/public/docs")

  @pages (for {section, pages} <- @sections, {key, name} <- pages do
            file = Path.join(@directory, (key || "overview") <> ".md")
            @external_resource file

            %{
              key: key,
              path: if(key, do: "/docs/" <> key, else: "/docs"),
              name: name,
              section: section,
              source: File.read!(file)
            }
          end)

  @paths Enum.map(@pages, & &1.path)

  @doc "Every docs address, overview first, in reading order."
  def paths, do: @paths

  @doc "Every page, overview first, in reading order."
  def all, do: @pages

  @doc "The sections with their pages, for the tabs and the sidebar."
  def sections,
    do: Enum.map(@sections, fn {section, _} -> {section, pages_in(section)} end)

  @doc "The page at `path`, or nil."
  def page(path), do: Enum.find(@pages, &(&1.path == path))

  @doc "The pages before and after `page`, in reading order; nil at either end."
  def neighbours(page) do
    index = Enum.find_index(@pages, &(&1.path == page.path))
    {if(index > 0, do: Enum.at(@pages, index - 1)), Enum.at(@pages, index + 1)}
  end

  defp pages_in(section), do: Enum.filter(@pages, &(&1.section == section))
end
