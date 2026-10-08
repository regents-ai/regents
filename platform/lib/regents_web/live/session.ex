defmodule RegentsWeb.Live.Session do
  @moduledoc false

  import Phoenix.LiveView,
    only: [attach_hook: 4, connected?: 1, get_connect_info: 2, redirect: 2]

  alias Regents.{AccessContext, Ens, Formation}
  alias Regents.Accounts.SessionAuthority
  alias Regents.Actors.Human

  @public_root "/"

  @doc """
  What the render knew, signed into the static LiveView token.

  `Phoenix.LiveView.Static.sign_token/2` signs with `Phoenix.Token`, which is
  integrity-only and readable by anyone holding the markup, so this carries the
  lineage-stable topic rather than the lineage itself: a digest that names the
  browser session without being able to authenticate as it. The route travels
  with it because a connected mount cannot otherwise learn it — `connect_info`
  `:uri` is the transport's own `/live/websocket` address and `socket.host_uri`
  carries no path, so only `handle_params` sees the page route, and that is too
  late to refuse a mount.

  Phoenix LiveView 1.2.7 hands `mount/3` `Map.merge(handshake_session,
  static_token_session)`, so these keys are the render's own and can never stand
  in for the authority the socket connected with.

  The client tag travels the same way: a socket's own peer is Fly's proxy, so
  only the render knows which client address its readings of Base count against.
  """
  def render_context(conn) do
    conn.assigns.current_lineage
    |> rendered_topic()
    |> Map.put("render_route", local_route(conn.request_path, conn.query_string))
    |> Map.put("client_tag", RegentsWeb.ClientAddress.tag(conn))
  end

  def on_mount(:load_human, _params, session, socket) do
    socket = Phoenix.Component.assign(socket, session_lease: nil)

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
  defp connected(socket, %{"render_topic" => rendered} = static, handshake),
    do: admit(socket, rendered, static["render_route"], SessionAuthority.claim(handshake))

  defp connected(socket, static, handshake) do
    if SessionAuthority.claim_shaped?(handshake),
      do: admit(socket, nil, static["render_route"], SessionAuthority.claim(handshake)),
      else: {:cont, assign_principal(socket, nil)}
  end

  defp admit(socket, _rendered, _route, nil), do: {:halt, redirect(socket, to: @public_root)}

  defp admit(socket, rendered, route, %{lineage: lineage} = claim) do
    with {^lineage, account} <- SessionAuthority.resolve(claim),
         ^rendered <- SessionAuthority.topic(lineage) do
      {:cont, hold(socket, lineage, account)}
    else
      {nil, nil} -> {:halt, redirect(socket, to: @public_root)}
      _other_session -> {:halt, redirect(socket, to: route)}
    end
  end

  defp hold(socket, _lineage, nil), do: assign_principal(socket, nil)

  # The lease holds no generation, because a same-account refresh advances it
  # beneath a live socket. Lineage, account
  # binding, revocation and the account's own provider evidence are re-read
  # every time, and the principal is rebuilt from that read rather than from the
  # struct the mount captured. Components receive the lease as `session_lease`
  # and check it on their own events (`check_component_events/1`); one that finds
  # it lapsed asks the page to withdraw the principal here.
  defp hold(socket, lineage, account) do
    lease = %{lineage: lineage, account_id: account.id}
    Phoenix.PubSub.subscribe(Regents.PubSub, Ens.topic(account.id))

    socket
    |> assign_principal(account)
    |> Phoenix.Component.assign(session_lease: lease)
    # The wallet's ENS name and picture arrive from Ethereum after sign-in has
    # already finished, so the page that is already open takes them as they land.
    # The view hears the same message afterwards, with the account re-read.
    |> attach_hook(:session_ens_identity, :handle_info, fn
      {:ens_lookup_finished, _account_id}, socket ->
        {:cont, reidentify(socket, leased(lease))}

      {__MODULE__, :component_lease_lapsed}, socket ->
        {:halt, withdraw(socket, leased(lease))}

      _message, socket ->
        {:cont, socket}
    end)
    |> attach_hook(:session_authority_params, :handle_params, fn _params, _uri, socket ->
      case leased(lease) do
        nil -> {:halt, redirect(lapsed(socket), to: @public_root)}
        account -> {:cont, assign_principal(socket, account)}
      end
    end)
    |> attach_hook(:session_authority_event, :handle_event, fn _event, _params, socket ->
      case leased(lease) do
        nil -> {:halt, lapsed(socket)}
        account -> {:cont, assign_principal(socket, account)}
      end
    end)
  end

  @doc """
  A LiveComponent's events never reach the page's own event hook, so every
  component that acts calls this from `mount/1`, and its page passes it the
  page's `session_lease` as `lease`. Each event first re-reads that lease, as
  the page does for its own events. A lapsed lease refuses the event with an
  empty reply, so a wallet step it was asked for is not built, and tells the
  page, which withdraws the principal and renders signed out. A page with no
  signed-in session passes a nil lease and its components act as before.
  """
  def check_component_events(socket) do
    attach_hook(socket, :session_authority_event, :handle_event, fn
      _event, _params, %{assigns: %{lease: nil}} = socket ->
        {:cont, socket}

      _event, _params, %{assigns: %{lease: lease}} = socket ->
        if leased(lease) do
          {:cont, socket}
        else
          send(self(), {__MODULE__, :component_lease_lapsed})
          {:halt, %{}, socket}
        end
    end)
  end

  # The page withdraws the principal when one of its components found the lease
  # lapsed, and keeps it when a read since then still finds the account.
  defp withdraw(socket, nil), do: lapsed(socket)
  defp withdraw(socket, account), do: assign_principal(socket, account)

  # A lease that has lapsed by the time a lookup lands is left to the next
  # navigation or action to withdraw, which is the only place that can also send
  # the page somewhere it is still allowed to be.
  defp reidentify(socket, nil), do: socket
  defp reidentify(socket, account), do: assign_principal(socket, account)

  # A lapsed lease withdraws the principal, so nothing downstream can still
  # present it as authority.
  defp lapsed(socket), do: assign_principal(socket, nil)

  defp leased(%{lineage: lineage, account_id: account_id}),
    do: SessionAuthority.leased_account(lineage, account_id)

  defp rendered_topic(nil), do: %{}
  defp rendered_topic(lineage), do: %{"render_topic" => SessionAuthority.topic(lineage)}

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
