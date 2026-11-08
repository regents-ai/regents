defmodule RegentsWeb.AgentGuides do
  @moduledoc """
  A page for each agent people pair with Regents Labs, at `/agents/SLUG`, and the
  list of them at `/agents`. Each agent is one committed Markdown file in
  `priv/public/agents/`, named by its slug: its harness value with `-` for `_`
  (`grok_bot` is `grok-bot`). Every file has one shape:

    * `# NAME`, then one line on how it pairs, which is also the page's search
      description and its line on `/agents`;
    * `## Set up`: what this agent needs beyond the agent guide. The agent guide
      with this section added is the agent's own skill, at `/agents/SLUG/skill.md`;
    * `## Questions`, then `## Troubleshooting`, ending with its Patchbay link,
      `https://patchbay.help/SLUG/troubleshooting`, or Patchbay's page for any
      agent, `https://patchbay.help/other/troubleshooting`, until Patchbay has one
      for it (IronClaw).

  Adding an agent is adding its file. Nothing here reads the database.

  Claude pairs only through the Claude connector, so its page, its skill and its
  line on `/agents` and in the sitemap exist only while the connector is switched
  on (`Regents.OAuth.enabled?/0`), read on each call; switched off,
  `/agents/claude` is not found like any other unknown agent.
  """

  alias RegentsWeb.PublicDocuments

  @directory Application.app_dir(:regents, "priv/public/agents")
  @files @directory |> Path.join("*.md") |> Path.wildcard() |> Enum.sort()
  for file <- @files, do: @external_resource(file)

  @guides Map.new(@files, fn file ->
            source = File.read!(file)
            ["# " <> name, rest] = String.split(source, "\n", parts: 2)
            [summary | _] = rest |> String.trim_leading() |> String.split("\n", parts: 2)
            [_, setup] = String.split(source, "\n## Set up\n", parts: 2)
            [setup | _] = String.split(setup, "\n## ", parts: 2)

            {Path.basename(file, ".md"),
             %{name: name, summary: summary, source: source, setup: String.trim(setup)}}
          end)

  # The order the pairing box offers them in.
  @slugs Enum.map(
           RegentAgents.Harness.featured(),
           &(&1 |> to_string() |> String.replace("_", "-"))
         )

  # The agents that pair only through the Claude connector, shown while it is on.
  @connector_only ["claude"]

  # Every agent the pairing box offers has a page, and every page is one it offers.
  @offered @slugs ++ @connector_only
  @unmatched (@offered -- Map.keys(@guides)) ++ (Map.keys(@guides) -- @offered)
  if @unmatched != [],
    do:
      raise(
        "priv/public/agents and Harness.featured/0 with Claude differ: #{inspect(@unmatched)}"
      )

  # A new agent's file recompiles this module, as an edited one does.
  def __mix_recompile__?,
    do: @directory |> Path.join("*.md") |> Path.wildcard() |> Enum.sort() != @files

  @doc "The page of the agent on `harness`."
  def path(harness), do: "/agents/" <> String.replace(to_string(harness), "_", "-")

  @doc "The list of agents, then every shown agent's page."
  def paths, do: ["/agents" | Enum.map(shown(), &("/agents/" <> &1))]

  @doc "The page at `path` as Markdown, or nil when it names no agent."
  def document("/agents"), do: %{title: "Agents", markdown: fill(index())}

  def document("/agents/" <> slug) do
    case guide(slug) do
      %{} = guide -> %{title: guide.name, markdown: fill(guide.source)}
      nil -> nil
    end
  end

  def document(_path), do: nil

  @doc "The page's title and search description."
  def page("/agents"),
    do:
      {"Agents", "Each agent's pairing with Regents Labs: its setup, common questions and help."}

  def page("/agents/" <> slug) do
    guide = Map.fetch!(@guides, slug)
    {guide.name, guide.summary}
  end

  @doc "The agent's skill: the agent guide with its Set up section added, or nil."
  def skill(slug) do
    case guide(slug) do
      %{} = guide ->
        PublicDocuments.skill() <> "\n## #{guide.name}\n\n" <> fill(guide.setup) <> "\n"

      nil ->
        nil
    end
  end

  # The agents shown now: Claude only while its connector is on.
  defp shown,
    do: if(Regents.OAuth.enabled?(), do: @offered, else: @slugs)

  defp guide(slug), do: if(slug in shown(), do: Map.fetch!(@guides, slug))

  defp index do
    lines =
      Enum.map_join(shown(), "\n", fn slug ->
        guide = @guides[slug]
        "- [#{guide.name}]({{origin}}/agents/#{slug}): #{guide.summary}"
      end)

    """
    # Agents

    Your agent pairs with your Regents account and works for you: it reads your account, name claims, staking position and Points. It can never use your wallet, change your account or pair other agents.

    1. Sign in, open [Pair New Agent]({{origin}}/pair) and choose your agent. Its pairing code works once, for ten minutes.
    2. Paste the message to your agent wherever you chat with it.
    3. It shows in your account menu under its name.

    Each page below is one agent's: how to set it up, answers to common questions and where to get help.

    #{lines}
    """
  end

  defp fill(markdown), do: String.replace(markdown, "{{origin}}", PublicDocuments.url(""))
end
