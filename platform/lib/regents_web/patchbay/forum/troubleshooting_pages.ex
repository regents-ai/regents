defmodule RegentsWeb.Patchbay.Forum.TroubleshootingPages do
  @moduledoc """
  Which agent programs have a troubleshooting page, and where each page and
  each agent's own Patchbay page are. A page is at
  /patchbay/SLUG/troubleshooting, SLUG being the shared harness id
  (`RegentAgents.Harness`) with dashes for underscores. The router reads this
  as it compiles, so it names nothing else of this application; what a page
  says is `RegentsWeb.Patchbay.Forum.Troubleshooting`'s.
  """

  alias RegentAgents.Harness

  # The harnesses with a page, each with its Patchbay agent page if it has one.
  @agent_pages %{
    claude_code: "claude",
    codex: nil,
    dots: "dots",
    grok_bot: "grokbot",
    hermes: "hermes",
    muse: "muse",
    nemoclaw: nil,
    openclaw: nil,
    pi: nil,
    other: nil
  }

  @doc "The harnesses with a troubleshooting page, in the shared harness order."
  def harnesses, do: Enum.filter(Harness.values(), &Map.has_key?(@agent_pages, &1))

  @doc "A harness's SLUG: its id with dashes for underscores."
  def slug(harness), do: String.replace(to_string(harness), "_", "-")

  @doc "A harness's troubleshooting page address."
  def path(harness), do: "/patchbay/" <> slug(harness) <> "/troubleshooting"

  @doc "The name a harness's page goes by: its own, or \"Any agent\" for the rest."
  def label(:other), do: "Any agent"
  def label(harness), do: Harness.label(harness)

  @doc "The id of a harness's own Patchbay agent page (`/patchbay/ID`), or nil."
  def agent_page(harness), do: Map.fetch!(@agent_pages, harness)

  @doc """
  A harness's own page on Patchbay: its agent page, or else its troubleshooting
  page, or else the troubleshooting page for any agent.
  """
  def page_path(harness) do
    case Map.fetch(@agent_pages, harness) do
      {:ok, id} when is_binary(id) -> "/patchbay/" <> id
      {:ok, nil} -> path(harness)
      :error -> path(:other)
    end
  end
end
