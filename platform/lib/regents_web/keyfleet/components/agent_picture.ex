defmodule RegentsWeb.Keyfleet.Components.AgentPicture do
  @moduledoc """
  The small round picture beside an agent's name: the picture the agent set,
  loaded from its bucket, or the one made from its wallet
  (`Regents.Keyfleet.Agents.Avatar.src/1`). The name beside it says who it is, so the
  picture itself says nothing to a screen reader.
  """
  use RegentsWeb, :html

  attr :src, :string, required: true

  def agent_picture(assigns) do
    ~H"""
    <img
      class="agent-picture"
      src={@src}
      alt=""
      width="24"
      height="24"
      loading="lazy"
      referrerpolicy="no-referrer"
    />
    """
  end
end
