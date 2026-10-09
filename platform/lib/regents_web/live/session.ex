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
  # beneath a live socket. Lineage, account binding, revocation, sign-in age and
  # the account's own provider evidence are re-read every time, and the
  # principal is rebuilt from that read rather than from the struct the mount
  # captured.
  #
  # Every navigation, event, message and background result is re-read the same
  # way before the page sees it, because a notification or a read can arrive
  # after the sign-in has outlived its lifetime with no navigation or event
  # between. A lapsed lease withdraws the principal, drops what arrived and
  # sends the page to the public root, which ends the page's process and with
  # it every private figure, subscription and read still running. The wallet's
  # ENS name and picture arrive from Ethereum after sign-in has finished, so a
  # finished lookup is one of those messages: it reads the account again, so
  # the header shows the name and picture it found, and the page hears it
  # afterwards. Components receive the lease as `session_lease` and check it on
  # their own events and results (`check_component_lease/2`); one that finds it
  # lapsed asks the page to do the same here.
  defp hold(socket, lineage, account) do
    lease = %{lineage: lineage, account_id: account.id}
    Phoenix.PubSub.subscribe(Regents.PubSub, Ens.topic(account.id))

    socket
    |> assign_principal(account)
    |> Phoenix.Component.assign(session_lease: lease)
    |> attach_hook(:session_authority_params, :handle_params, fn _params, _uri, socket ->
      recheck(socket, lease)
    end)
    |> attach_hook(:session_authority_event, :handle_event, fn _event, _params, socket ->
      recheck(socket, lease)
    end)
    |> attach_hook(:session_authority_info, :handle_info, fn
      {__MODULE__, :component_lease_lapsed}, socket ->
        {_cont_or_halt, socket} = recheck(socket, lease)
        {:halt, socket}

      _message, socket ->
        recheck(socket, lease)
    end)
    |> attach_hook(:session_authority_async, :handle_async, fn _name, _result, socket ->
      recheck(socket, lease)
    end)
  end

  @doc """
  A LiveComponent's events and background results never reach the page's own
  hooks, so every component that acts calls this from `mount/1`, and its page
  passes it the page's `session_lease` as `lease`. Each event and each result
  first re-reads that lease, as the page does for its own. A current lease
  hands `take_account`, the component's own function (the one its `update/2`
  uses too), the account as it reads now, and the component rebuilds from it
  the wallets and actor it acts with, so nothing acts on a wallet list or actor
  captured earlier. A lapsed lease refuses the event with an empty reply, so a
  wallet step it was asked for is not built, or drops the result unseen, and
  tells the page, which withdraws the principal and goes to the public root. A
  page with no signed-in session passes a nil lease and its components act on
  what the page gave them.
  """
  def check_component_lease(socket, take_account) do
    socket
    |> attach_hook(:session_authority_event, :handle_event, fn _event, _params, socket ->
      case component_account(socket) do
        :lapsed -> {:halt, %{}, socket}
        account -> {:cont, take(socket, take_account, account)}
      end
    end)
    |> attach_hook(:session_authority_async, :handle_async, fn _name, _result, socket ->
      case component_account(socket) do
        :lapsed -> {:halt, socket}
        account -> {:cont, take(socket, take_account, account)}
      end
    end)
  end

  defp component_account(%{assigns: %{lease: nil}}), do: :signed_out

  defp component_account(%{assigns: %{lease: lease}}) do
    case SessionAuthority.leased_account(lease.lineage, lease.account_id) do
      nil ->
        send(self(), {__MODULE__, :component_lease_lapsed})
        :lapsed

      account ->
        account
    end
  end

  defp take(socket, _take_account, :signed_out), do: socket
  defp take(socket, take_account, account), do: take_account.(socket, account)

  defp recheck(socket, lease) do
    case SessionAuthority.leased_account(lease.lineage, lease.account_id) do
      nil -> {:halt, socket |> assign_principal(nil) |> redirect(to: @public_root)}
      account -> {:cont, assign_principal(socket, account)}
    end
  end

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
