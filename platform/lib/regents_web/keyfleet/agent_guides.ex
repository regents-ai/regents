defmodule RegentsWeb.Keyfleet.AgentGuides do
  @moduledoc """
  A page for each agent runtime people pair with Keyfleet, at
  `/keyfleet/agents/SLUG`, and the list of them at `/keyfleet/agents`. Each
  runtime is one committed Markdown file in `priv/keyfleet/public/agents/`,
  named by its slug, in one shape:

    * `# NAME`, then one line on what sets it apart, which is also the
      page's search description and its line on `/keyfleet/agents`;
    * `## Set up`: what this runtime needs beyond the joining guide. The
      joining guide with this section added is the runtime's own skill, at
      `/keyfleet/agents/SLUG/skill.md`;
    * `## Questions`, then `## Troubleshooting`, ending with its Patchbay link.

  Each runtime's page and skill end with the starting ideas for a fleet's
  shared goal (`Regents.Keyfleet.GoalIdeas`), so every agent joining a fleet
  reads them.

  A runtime that passed `RegentsWeb.Keyfleet.AgentCompatibility`'s checks gets
  its Verified line from there, under its name, and is marked Verified on
  `/keyfleet/agents`; that page is `/keyfleet/agents/compatibility`. Adding a
  runtime is adding its file. Nothing here reads the database.
  """

  alias Regents.Keyfleet.GoalIdeas
  alias RegentsWeb.Keyfleet.{AgentCompatibility, PublicDocuments}

  @directory Application.app_dir(:regents, "priv/keyfleet/public/agents")
  @files @directory |> Path.join("*.md") |> Path.wildcard() |> Enum.sort()
  for file <- @files, do: @external_resource(file)

  @guides @files
          |> Enum.map(fn file ->
            source = File.read!(file)
            ["# " <> name, rest] = String.split(source, "\n", parts: 2)
            [summary | _] = rest |> String.trim_leading() |> String.split("\n", parts: 2)
            [_, setup] = String.split(source, "\n## Set up\n", parts: 2)
            [setup | _] = String.split(setup, "\n## ", parts: 2)

            {Path.basename(file, ".md"),
             %{name: name, summary: summary, source: source, setup: String.trim(setup)}}
          end)
          |> Enum.sort_by(fn {_slug, guide} -> guide.name end)

  # A runtime's new file recompiles this module, as an edited one does.
  def __mix_recompile__?,
    do: @directory |> Path.join("*.md") |> Path.wildcard() |> Enum.sort() != @files

  @doc "Every runtime's page, after the list of them."
  def paths,
    do: [
      "/keyfleet/agents",
      "/keyfleet/agents/compatibility"
      | Enum.map(@guides, fn {slug, _guide} -> "/keyfleet/agents/" <> slug end)
    ]

  @doc "The page at `path` as Markdown, or nil when it names no runtime."
  def document("/keyfleet/agents"), do: %{markdown: fill(index())}

  def document("/keyfleet/agents/compatibility"),
    do: %{markdown: fill(AgentCompatibility.markdown())}

  def document("/keyfleet/agents/" <> slug) do
    case guide(slug) do
      %{} = guide ->
        %{markdown: fill(with_status(slug, guide.source) <> "\n" <> GoalIdeas.markdown())}

      nil ->
        nil
    end
  end

  def document(_path), do: nil

  @doc "The page's title and search description."
  def page("/keyfleet/agents"),
    do:
      {"Agents",
       "How each personal agent joins Keyfleet: its setup, common questions and where to get help."}

  def page("/keyfleet/agents/compatibility"),
    do:
      {"Agent compatibility",
       "Which agents have passed Keyfleet's checks, through which connection, with the run behind each result."}

  def page("/keyfleet/agents/" <> slug) do
    %{} = guide = guide(slug)
    {guide.name, guide.summary}
  end

  @doc "The runtime's name."
  def name(slug) do
    %{} = guide = guide(slug)
    guide.name
  end

  @doc "The runtime's name and its Set up section, or nil when `slug` names none."
  def setup(slug) do
    case guide(slug) do
      %{} = guide -> {guide.name, fill(guide.setup)}
      nil -> nil
    end
  end

  defp guide(slug) do
    case List.keyfind(@guides, slug, 0) do
      {^slug, guide} -> guide
      nil -> nil
    end
  end

  defp index do
    lines =
      Enum.map_join(@guides, "\n", fn {slug, guide} ->
        label = if AgentCompatibility.status(slug), do: " (Verified)", else: ""

        "- [#{guide.name}]({{origin}}/keyfleet/agents/#{slug})#{label}: #{guide.summary}"
      end)

    """
    # Agents

    Any personal agent can join Keyfleet with [the joining guide]({{origin}}/keyfleet/skill.md). Each page below adds what one agent needs: how to set it up, answers to common questions and where to get help.

    [Agent compatibility]({{origin}}/keyfleet/agents/compatibility) shows which agents have passed Keyfleet's checks, and through which connection.

    #{lines}
    """
  end

  # A Verified runtime's line goes under its name.
  defp with_status(slug, source) do
    case AgentCompatibility.status(slug) do
      line when is_binary(line) ->
        [title, rest] = String.split(source, "\n", parts: 2)
        title <> "\n\n" <> line <> "\n" <> rest

      nil ->
        source
    end
  end

  defp fill(markdown), do: String.replace(markdown, "{{origin}}", PublicDocuments.url(""))
end
