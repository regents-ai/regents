defmodule AshPlatformWeb.Live.Session do
  @moduledoc false

  import Phoenix.LiveView,
    only: [attach_hook: 4, connected?: 1, get_connect_info: 2, redirect: 2]

  alias AshPlatform.{AccessContext, Formation}
  alias AshPlatform.Accounts.SessionAuthority
  alias AshPlatform.Actors.Human

  @doc """
  The lineage the page was rendered for, signed into the static LiveView token.

  Phoenix LiveView 1.2.7 hands `mount/3` `Map.merge(handshake_session,
  static_token_session)`, so this uses its own key and only ever names a lineage
  the render already proved current. A page rendered without one cannot make a
  connected mount reload, which is what keeps the reload rule loop-free.
  """
  def render_lineage(%{assigns: %{current_lineage: nil}}), do: %{}
  def render_lineage(%{assigns: %{current_lineage: lineage}}), do: %{"render_lineage" => lineage}

  def on_mount(:load_human, _params, session, socket) do
    if connected?(socket) do
      connected(
        socket,
        session["render_lineage"],
        SessionAuthority.claim(get_connect_info(socket, :session))
      )
    else
      {:cont, assign_principal(socket, disconnected_account(session))}
    end
  end

  # A page rendered for no lineage is an ordinary anonymous visit and mounts as
  # one. Otherwise the markup was built for a browser session, and only that
  # session's exactly current cookie may drive the socket: anything else is
  # reloaded once over HTTP rather than quietly continuing as anonymous.
  defp connected(socket, nil, _handshake), do: {:cont, assign_principal(socket, nil)}

  defp connected(socket, lineage, %{lineage: lineage, generation: generation} = handshake) do
    case SessionAuthority.resolve(handshake) do
      {nil, nil} -> {:cont, reload(socket)}
      {^lineage, account} -> {:cont, hold(socket, lineage, generation, account)}
    end
  end

  defp connected(socket, _rendered, _other_lineage), do: {:cont, reload(socket)}

  defp reload(socket) do
    socket
    |> assign_principal(nil)
    |> attach_hook(:session_authority_reload, :handle_params, fn _params, uri, socket ->
      {:halt, redirect(socket, to: local_route(uri))}
    end)
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
      {:cont, assign_principal(socket, leased(lease))}
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

  defp disconnected_account(session) do
    {_lineage, account} = session |> SessionAuthority.claim() |> SessionAuthority.resolve()
    account
  end

  defp local_route(uri) do
    %URI{path: path, query: query} = URI.parse(uri)
    URI.to_string(%URI{path: path, query: query})
  end

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
