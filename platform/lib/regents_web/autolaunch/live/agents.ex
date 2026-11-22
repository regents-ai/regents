defmodule RegentsWeb.Autolaunch.Live.Agents do
  @moduledoc """
  The account menu's agents (`RegentsWeb.Autolaunch.MenuAgents`) and the pairing window's
  box (`RegentsWeb.Autolaunch.PairingBox`) hear when an agent pairs, checks in or is
  unpaired on any Regent site (`RegentAgents.topic/1`, which
  `RegentAgents.Listener` feeds), as the template's shell does, on every LiveView
  page, so a code on screen gives way to the agent that used it. The Agents page
  reads its agents again (`RegentsWeb.Autolaunch.AccountAgentsLive.read_agents/1`), and
  the pairing link's page updates its own box.

  It runs after the session hook, so it listens for the account the mount
  proved, and the session hook re-reads the sign-in before each change lands
  here.
  """

  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1]

  def on_mount(:agents, _params, _session, socket) do
    {:cont,
     socket
     |> listen()
     |> attach_hook(:agents_changed, :handle_info, fn
       :agents_changed, socket -> {:halt, socket}
       _message, socket -> {:cont, socket}
     end)}
  end

  defp listen(socket) do
    with true <- connected?(socket),
         {:human, account} <- socket.assigns.access_context.principal do
      Phoenix.PubSub.subscribe(Regents.PubSub, RegentAgents.topic(account.privy_user_id))
    end

    socket
  end
end
