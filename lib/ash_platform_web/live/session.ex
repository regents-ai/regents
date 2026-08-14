defmodule AshPlatformWeb.Live.Session do
  @moduledoc false

  import Phoenix.LiveView,
    only: [attach_hook: 4, connected?: 1, get_connect_info: 2, redirect: 2]

  alias AshPlatform.{AccessContext, Formation}
  alias AshPlatform.Accounts.SessionAuthority
  alias AshPlatform.Actors.Human

  @public_root "/"

  @doc """
  What the render knew, signed into the static LiveView token.

  Phoenix LiveView 1.2.7 hands `mount/3` `Map.merge(handshake_session,
  static_token_session)`, so these use their own keys and can never stand in for
  the authority the socket connected with. The lineage is named only while that
  render's own claim was current. The route travels with them because a connected
  mount cannot otherwise learn it: `connect_info` `:uri` is the transport's own
  `/live/websocket` address and `socket.host_uri` carries no path, so only
  `handle_params` sees the page route and that is too late to refuse a mount.
  """
  def render_context(conn) do
    conn.assigns.current_lineage
    |> rendered_lineage()
    |> Map.put("render_route", local_route(conn.request_path, conn.query_string))
  end

  def on_mount(:load_human, _params, session, socket) do
    if connected?(socket) do
      connected(socket, session, get_connect_info(socket, :session))
    else
      {:cont, assign_principal(socket, disconnected_account(session))}
    end
  end

  # The cookie the socket connected with is the only authority, and a mount that
  # cannot honour it is refused there and then rather than left to a later hook.
  # An exactly current claim drives the socket when the page was rendered for its
  # lineage; when it was not, one full request for the same route realigns them.
  # Anything else — a claim-shaped handshake that will not parse, one the
  # authority refuses, or none at all under a page that named a lineage — lands
  # on the public root, which is outside the product shell and so cannot raise
  # the same rejection again.
  defp connected(socket, %{"render_lineage" => rendered} = static, handshake),
    do: admit(socket, rendered, static["render_route"], SessionAuthority.claim(handshake))

  defp connected(socket, static, handshake) do
    if SessionAuthority.claim_shaped?(handshake),
      do: admit(socket, nil, static["render_route"], SessionAuthority.claim(handshake)),
      else: {:cont, assign_principal(socket, nil)}
  end

  defp admit(socket, _rendered, _route, nil), do: {:halt, redirect(socket, to: @public_root)}

  defp admit(socket, rendered, route, %{lineage: lineage, generation: generation} = claim) do
    case SessionAuthority.resolve(claim) do
      {nil, nil} -> {:halt, redirect(socket, to: @public_root)}
      {^rendered, account} -> {:cont, hold(socket, lineage, generation, account)}
      {^lineage, _account} -> {:halt, redirect(socket, to: route)}
    end
  end

  defp hold(socket, _lineage, _generation, nil), do: assign_principal(socket, nil)

  # The lease records the generation the mount proved, which later revalidation
  # deliberately does not re-require: a same-account refresh advances it beneath
  # a live socket. Lineage, account binding, revocation and the account's own
  # provider evidence are re-read every time, and the principal is rebuilt from
  # that read rather than from the struct the mount captured.
  defp hold(socket, lineage, generation, account) do
    lease = %{lineage: lineage, account_id: account.id, generation_at_mount: generation}

    socket
    |> assign_principal(account)
    |> attach_hook(:session_authority_params, :handle_params, fn _params, _uri, socket ->
      case leased(lease) do
        nil -> {:halt, redirect(assign_principal(socket, nil), to: @public_root)}
        account -> {:cont, assign_principal(socket, account)}
      end
    end)
    |> attach_hook(:session_authority_event, :handle_event, fn _event, _params, socket ->
      case leased(lease) do
        nil -> {:halt, assign_principal(socket, nil)}
        account -> {:cont, assign_principal(socket, account)}
      end
    end)
  end

  defp leased(%{lineage: lineage, account_id: account_id}),
    do: SessionAuthority.leased_account(lineage, account_id)

  defp rendered_lineage(nil), do: %{}
  defp rendered_lineage(lineage), do: %{"render_lineage" => lineage}

  defp disconnected_account(session) do
    {_lineage, account} = session |> SessionAuthority.claim() |> SessionAuthority.resolve()
    account
  end

  defp local_route(path, ""), do: path
  defp local_route(path, query), do: path <> "?" <> query

  defp assign_principal(socket, account) do
    access_context = access_context(account)
    regent = load_regent(access_context)

    Phoenix.Component.assign(socket,
      access_context: access_context,
      account_control: AccessContext.account_control(access_context, regent),
      current_regent: regent
    )
  end

  defp access_context(nil), do: AccessContext.anonymous()
  defp access_context(account), do: AccessContext.human(account)

  defp load_regent(%AccessContext{principal: {:human, account}}) do
    case Formation.get_my_regent(actor: %Human{human_account_id: account.id}) do
      {:ok, regent} -> regent
      _no_regent -> nil
    end
  end

  defp load_regent(_access_context), do: nil
end
