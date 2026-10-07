defmodule RegentAgents.HumanBacking do
  @moduledoc """
  Whether a person verified with World ID stands behind an agent, and how many
  agents that same person stands behind, from the `agentBook` the SIWA service
  sends with every verified agent request.

  The SIWA service sends `null` when no verified person stands behind the
  agent, or the person's World ID number and their agent count once the agent
  has signed to accept that person and World still names them. Each verified
  request saves what it was sent onto the paired agent, and `null` clears it,
  so pages show the saved values and never ask the SIWA service.

  The person's number only groups one person's agents. It is never shown,
  logged or answered to anyone. Every Regent site describes an agent to agents
  with `describe/1`'s two fields, under these names.
  """

  @type t :: %{human_id: String.t() | nil, same_person_agent_count: pos_integer() | nil}

  @spec read(map() | nil) :: {:ok, t()} | :error
  def read(nil), do: {:ok, %{human_id: nil, same_person_agent_count: nil}}

  def read(%{"humanId" => "0x" <> _number = human_id, "agentCount" => count})
      when is_integer(count) and count >= 1,
      do: {:ok, %{human_id: human_id, same_person_agent_count: count}}

  def read(_other), do: :error

  @doc "The two fields every Regent site tells agents and shows people."
  @spec describe(%{human_id: String.t() | nil, same_person_agent_count: pos_integer() | nil}) ::
          %{human_backed: boolean(), same_person_agent_count: pos_integer() | nil}
  def describe(%{human_id: human_id, same_person_agent_count: count}),
    do: %{human_backed: is_binary(human_id), same_person_agent_count: count}
end
