defmodule RegentsWeb.Autolaunch.Components.LaunchKindChoice do
  @moduledoc "The switch between the two launches, beside the title on both Create pages."
  use RegentsWeb, :html

  attr :current, :atom, required: true, values: [:memestock, :revstake]

  @doc "Memestock or Revstake, as links to each Create page, with the open one marked."
  def launch_kind_choice(assigns) do
    ~H"""
    <nav class="launch-kind" aria-label="Launch type">
      <.link navigate={~p"/autolaunch/create"} aria-current={@current == :memestock && "page"}>
        Memestock
      </.link>
      <.link navigate={~p"/autolaunch/agent-business"} aria-current={@current == :revstake && "page"}>
        Revstake
      </.link>
    </nav>
    """
  end
end
