defmodule RegentsWeb.Techtree.AgentGuides do
  @moduledoc """
  A page for each agent people pair with Techtree, at `/techtree/agents/SLUG`, the
  list of them at `/techtree/agents`, and the Techtree skill at
  `/techtree/skill.md`. Each agent is one committed Markdown file in
  `priv/techtree/public/agents/`, named by its slug: its harness value with `-`
  for `_` (`grok_bot` is `grok-bot`). Every file has one shape:

    * `# NAME`, then one line on how it pairs, which is also the page's search
      description and its line on `/techtree/agents`;
    * `## Set up`: what this agent needs beyond the Techtree skill. The Techtree
      skill (`priv/techtree/public/skill.md`) with this section added is the
      agent's own skill, at `/techtree/agents/SLUG/skill.md`;
    * `## Questions`, then `## Troubleshooting`, ending with its Patchbay link.

  `{{origin}}` in these files and in the skill is this site's address, filled in
  when served. Adding an agent is adding its file. Nothing here reads the database.
  """

  @directory Application.app_dir(:regents, "priv/techtree/public/agents")
  @files @directory |> Path.join("*.md") |> Path.wildcard() |> Enum.sort()
  for file <- @files, do: @external_resource(file)

  @skill_file Application.app_dir(:regents, "priv/techtree/public/skill.md")
  @external_resource @skill_file
  @skill File.read!(@skill_file)

  @guides Map.new(@files, fn file ->
            source = File.read!(file)
            ["# " <> name, rest] = String.split(source, "\n", parts: 2)
            [summary | _] = rest |> String.trim_leading() |> String.split("\n", parts: 2)
            [_, setup] = String.split(source, "\n## Set up\n", parts: 2)
            [setup | _] = String.split(setup, "\n## ", parts: 2)

            {Path.basename(file, ".md"),
             %{name: name, summary: summary, source: source, setup: String.trim(setup)}}
          end)

  # The agents the pairing box offers, as slugs, in its order.
  @slugs Enum.map(
           RegentAgents.Harness.featured(),
           &(&1 |> to_string() |> String.replace("_", "-"))
         )

  # Every agent the pairing box offers has a page, and every page is one it offers.
  @unmatched (@slugs -- Map.keys(@guides)) ++ (Map.keys(@guides) -- @slugs)
  if @unmatched != [],
    do: raise("priv/techtree/public/agents and Harness.featured/0 differ: #{inspect(@unmatched)}")

  # A new agent's file recompiles this module, as an edited one does.
  def __mix_recompile__?,
    do: @directory |> Path.join("*.md") |> Path.wildcard() |> Enum.sort() != @files

  @doc "The list of agents, then every agent's page."
  @spec paths() :: [String.t()]
  def paths, do: ["/techtree/agents" | Enum.map(@slugs, &("/techtree/agents/" <> &1))]

  @doc "The page at `path` as Markdown, or nil when it names no agent."
  @spec document(String.t()) :: %{title: String.t(), markdown: String.t()} | nil
  def document("/techtree/agents"), do: %{title: "Agents", markdown: fill(index())}

  def document("/techtree/agents/" <> slug) do
    case @guides do
      %{^slug => guide} -> %{title: guide.name, markdown: fill(guide.source)}
      %{} -> nil
    end
  end

  def document(_path), do: nil

  @doc "The search description of the list or of an agent's page."
  @spec description(String.t()) :: String.t()
  def description("/techtree/agents"),
    do: "Each agent's pairing with Techtree: its setup, common questions and help."

  def description("/techtree/agents/" <> slug), do: Map.fetch!(@guides, slug).summary

  @doc "The Techtree skill served at `/techtree/skill.md`."
  @spec skill_guide() :: String.t()
  def skill_guide, do: fill(@skill)

  @doc "The agent's skill: the Techtree skill with its Set up section added, or nil."
  @spec skill(String.t()) :: String.t() | nil
  def skill(slug) do
    case @guides do
      %{^slug => guide} -> fill(@skill <> "\n## On #{guide.name}\n\n" <> guide.setup <> "\n")
      %{} -> nil
    end
  end

  defp index do
    lines =
      Enum.map_join(@slugs, "\n", fn slug ->
        guide = @guides[slug]
        "- [#{guide.name}]({{origin}}/techtree/agents/#{slug}): #{guide.summary}"
      end)

    """
    # Agents

    Your agent pairs with your Techtree account and works for you: it publishes and withdraws your Results and reads your Points. It can never use your wallet, change your account or pair other agents.

    1. Sign in, open [Pair New Agent]({{origin}}/account/agents) on your Agents page and choose your agent. Its pairing code works once, for ten minutes.
    2. Paste the message to your agent wherever you chat with it.
    3. It shows in your account menu under its name.

    Each page below is one agent's: how to set it up, answers to common questions and where to get help.

    #{lines}
    """
  end

  defp fill(markdown), do: String.replace(markdown, "{{origin}}", RegentsWeb.Endpoint.url())
end
