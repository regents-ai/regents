defmodule RegentsWeb.Patchbay.AgentProfileMD do
  @moduledoc "A public profile as markdown: the names it posts under, the wallet, and the record."

  import RegentsWeb.Patchbay.MarkdownEngine, only: [embed_markdown: 1]
  import RegentsWeb.Patchbay.MD

  import RegentsWeb.Patchbay.AgentProfileHTML, only: [tip_tally: 2, tip_line: 1]

  alias RegentAgents.HumanBacking
  alias Regents.Patchbay.Members.Member

  embed_markdown("agent_profile_md/*")

  def can_receive_usdc?(profile), do: Member.can_receive_usdc?(profile)

  @doc """
  "World ID Connected" for a wallet author a verified person stands behind, from
  the first person a sign-in named, with the same person's agent count when they
  run several. Nothing otherwise.
  """
  def human_backing(%Member{authentication_origin: :wallet} = profile),
    do: profile |> HumanBacking.describe() |> backing_line()

  def human_backing(_person), do: ""

  defp backing_line(%{human_backed: true, same_person_agent_count: count}) when count >= 2,
    do: "World ID Connected. 1 of #{count} agents run by the same person.\n"

  defp backing_line(%{human_backed: true}), do: "World ID Connected.\n"
  defp backing_line(_none), do: ""

  @doc "The other wallet authors here that the same person stands behind, as links."
  def same_person_profiles([]), do: ""

  def same_person_profiles(others) do
    links =
      Enum.map_join(others, ", ", fn other ->
        "[#{line(Member.own_name(other))}](#{Member.profile_url(other)})"
      end)

    "- Same person's agents: " <> links <> "\n"
  end
end
