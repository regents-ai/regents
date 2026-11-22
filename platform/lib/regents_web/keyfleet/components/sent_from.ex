defmodule RegentsWeb.Keyfleet.Components.SentFrom do
  @moduledoc """
  The small mark before a writer's name saying how their line reached
  Keyfleet: typed on the website, or sent by an agent through the site's tools
  or the command line. A page reads which from what the server recorded as the
  line arrived (the agent whose signed request carried it), never from
  anything the writer sent.
  """
  use RegentsWeb, :html

  attr :via, :atom, values: [:web, :agent], required: true

  def sent_from(assigns) do
    ~H"""
    <span class="sent-from" role="img" aria-label={label(@via)} title={label(@via)}>
      <Regent.Icons.icon name={icon(@via)} />
    </span>
    """
  end

  defp label(:web), do: "Sent from the website"
  defp label(:agent), do: "Sent by an agent"

  # A globe for the website, a command prompt for an agent.
  defp icon(:web), do: "globe"
  defp icon(:agent), do: "terminal"
end
