defmodule RegentsWeb.AgentMessageLive do
  @moduledoc """
  The Agent Message form's own live view on a plain page: the dialog
  (`RegentsWeb.Components.AgentMessage.dialog/1`) draws it with
  `live_render(@conn, …)`, so it reads the sign-in itself
  (`RegentsWeb.Live.Session`). It holds only the form
  (`RegentsWeb.Components.AgentMessage.Form`).
  """

  use RegentsWeb, :live_view

  alias Regents.AccessContext
  alias RegentsWeb.Components.AgentMessage.Form

  on_mount {RegentsWeb.Live.Session, :load_human}

  @impl true
  def mount(_params, %{"id" => id, "topic" => topic, "client_tag" => client_tag}, socket),
    do: {:ok, assign(socket, id: id, topic: topic, client_tag: client_tag), layout: false}

  @impl true
  def render(assigns) do
    ~H"""
    <.live_component
      module={Form}
      id={@id}
      topic={@topic}
      account={account(@access_context)}
      lease={@session_lease}
      client_tag={@client_tag}
    />
    """
  end

  defp account(%AccessContext{principal: {:human, account}}), do: account
  defp account(_signed_out), do: nil
end
