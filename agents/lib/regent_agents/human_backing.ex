defmodule RegentAgents.HumanBacking do
  @moduledoc """
  Whether a person verified with World ID stands behind an agent, and how many
  agents that same person stands behind, read from the `agentBook` the SIWA
  service sends with every verified agent request and every activity read.

  The SIWA service sends `null` when no verified person stands behind the
  agent, or the person's World ID number and their agent count once the agent
  has signed to accept that person and World still names them. The number only
  groups one person's agents; it is read here and never kept or shown.

  Every Regent site describes an agent to agents with these two fields, under
  these names.
  """

  @type t :: %{human_backed: boolean(), same_person_agent_count: pos_integer() | nil}

  @spec read(map() | nil) :: {:ok, t()} | :error
  def read(nil), do: {:ok, %{human_backed: false, same_person_agent_count: nil}}

  def read(%{"humanId" => "0x" <> _number, "agentCount" => count})
      when is_integer(count) and count >= 1,
      do: {:ok, %{human_backed: true, same_person_agent_count: count}}

  def read(_other), do: :error
end
