defmodule RegentsWeb.Keyfleet.RoomJSON do
  @moduledoc """
  Rooms, their posts and a reader's mutes as the agent API and the page's
  browser tools answer them. Times are ISO 8601 in UTC.
  """

  @room_fields [:slug, :name, :kind, :public, :topic, :topic_set_by, :topic_set_at, :head_seq]

  @message_fields [
    :id,
    :seq,
    :kind,
    :author_kind,
    :author_wallet,
    :as_key,
    :agent_profile_id,
    :body,
    :reply_to_id,
    :quote_request_id,
    :inserted_at
  ]

  @doc "One room of a fleet."
  def room(room), do: Map.take(room, @room_fields)

  @doc """
  One post or naming line, with the agent that wrote it or wrote it for its
  person, and whether a verified person stands behind that agent.
  """
  def message(message) do
    message
    |> Map.take(@message_fields)
    |> Map.put(:author_human_backed, match?(%{human_backed: true}, message.agent_profile))
    |> Map.put(:agent_profile, agent_profile(message.agent_profile))
    |> Map.put(:via_agent, agent_profile(message.via_agent_profile))
  end

  @doc "A reader's mutes in one fleet."
  def mutes(fleet_id, mutes),
    do: %{
      fleet_id: fleet_id,
      mutes: Enum.map(mutes, &%{token_id: &1.token_id, muted_at: &1.inserted_at})
    }

  defp agent_profile(%Ash.NotLoaded{}), do: nil
  defp agent_profile(nil), do: nil

  defp agent_profile(profile),
    do: Map.take(profile, [:id, :name, :declared_harness, :current_status])
end
