defmodule RegentsWeb.Patchbay.CurrentProfile do
  @moduledoc """
  Bridges Regents' signed-in `HumanAccount` session (`SessionAuthority` /
  `RegentsWeb.Live.Session`) to Patchbay's `Regents.Patchbay.Members.Member`
  profile for Patchbay LiveViews and controllers.

  When mounted after `{RegentsWeb.Live.Session, :load_human}` inside a router
  `live_session`, this hook resolves `:current_profile` from the session's
  already-verified `:access_context` on both disconnected SSR and connected
  mounts, and keeps `:current_profile` synchronized without clobbering
  `Live.Session`'s `:session_lease` or `:signed_out_reason`.

  When mounted standalone (for `live_render` child LiveViews such as
  `AgentMessageLive` or `ModerationLive`), it resolves the session on SSR and
  verifies the live WebSocket handshake cookie on connect.
  """

  import Phoenix.Component, only: [assign: 2, assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1, get_connect_info: 2, redirect: 2]

  alias Regents.Account.AccessContext
  alias Regents.Account.Accounts.SessionAuthority
  alias Regents.Patchbay.Members
  alias Regents.Patchbay.Members.Member
  alias RegentsWeb.VisitLog

  @public_root "/patchbay/app"
  @wallet_pattern ~r/\A0x[0-9a-f]{40}\z/

  def render_context(conn) do
    conn
    |> VisitLog.session()
    |> Map.merge(rendered_topic(conn.assigns[:current_lineage]))
    |> Map.put("render_route", local_route(conn.request_path, conn.query_string))
  end

  def on_mount(mode, _params, session, socket) when mode in [:default, :account] do
    if Map.has_key?(socket.assigns, :access_context) do
      mount_from_session_assigns(socket)
    else
      mount_standalone(socket, session, mode)
    end
  end

  @doc "Resolves the Patchbay member from a disconnected render session without writing a lease."
  @spec disconnected_profile(map()) :: Member.t() | nil
  def disconnected_profile(session) when is_map(session) do
    case session |> SessionAuthority.claim() |> SessionAuthority.resolve() do
      {_lineage, %{} = account} -> member_for_account(account)
      _signed_out -> nil
    end
  rescue
    _ -> nil
  end

  def disconnected_profile(_other), do: nil

  @doc "Resolves profile and lease from a LiveView socket's handshake session (falling back to static session)."
  def connect_lease(socket, session) do
    handshake = get_connect_info(socket, :session) || session
    connect_lease(handshake)
  end

  def connect_lease(session) do
    case session |> SessionAuthority.claim() |> SessionAuthority.resolve() do
      {lineage, %{} = account} ->
        case member_for_account(account) do
          %Member{} = profile -> {profile, lease(lineage, account, profile)}
          nil -> {nil, nil}
        end

      _signed_out ->
        {nil, nil}
    end
  rescue
    _ -> {nil, nil}
  end

  def leased_profile(nil), do: nil

  def leased_profile(%{lineage: lineage, account_id: account_id}) do
    case SessionAuthority.leased_account(lineage, account_id) do
      %{} = account -> member_for_account(account)
      nil -> nil
    end
  rescue
    _ -> nil
  end

  def leased_profile(_other), do: nil

  @doc "Finds or provisions the active Patchbay member for a signed-in Regents account."
  @spec member_for_account(map() | nil) :: Member.t() | nil
  def member_for_account(nil), do: nil

  def member_for_account(%{privy_user_id: privy_user_id} = account)
      when is_binary(privy_user_id) do
    case Members.get_profile_by_privy_user_id(privy_user_id) do
      {:ok, %Member{} = member} ->
        attach_account_wallets(member, account)

      {:ok, nil} ->
        provision_member(privy_user_id, primary_wallet(account), account)

      _other ->
        nil
    end
  rescue
    _ -> nil
  end

  def member_for_account(_other), do: nil

  def check_component_lease(socket, take_profile) do
    socket
    |> attach_hook(:current_profile_event, :handle_event, fn _event, _params, socket ->
      case component_profile(socket) do
        :lapsed -> {:halt, %{}, socket}
        profile -> {:cont, take(socket, take_profile, profile)}
      end
    end)
    |> attach_hook(:current_profile_async, :handle_async, fn _name, _result, socket ->
      case component_profile(socket) do
        :lapsed -> {:halt, socket}
        profile -> {:cont, take(socket, take_profile, profile)}
      end
    end)
  end

  # Mounted after RegentsWeb.Live.Session: reuse its verified :access_context and
  # :session_lease instead of creating a competing lease or wiping SSR auth state.
  defp mount_from_session_assigns(socket) do
    socket = sync_profile_from_access_context(socket)

    if connected?(socket) do
      {:cont,
       socket
       |> attach_hook(:current_profile_sync_event, :handle_event, fn _event, _params, socket ->
         {:cont, sync_profile_from_access_context(socket)}
       end)
       |> attach_hook(:current_profile_sync_info, :handle_info, fn _message, socket ->
         {:cont, sync_profile_from_access_context(socket)}
       end)
       |> attach_hook(:current_profile_sync_async, :handle_async, fn _name, _result, socket ->
         {:cont, sync_profile_from_access_context(socket)}
       end)
       |> sync_navigation()}
    else
      {:cont, socket}
    end
  end

  defp sync_navigation(%{router: nil} = socket), do: socket

  defp sync_navigation(socket) do
    attach_hook(socket, :current_profile_sync_params, :handle_params, fn _params, _uri, socket ->
      {:cont, sync_profile_from_access_context(socket)}
    end)
  end

  defp sync_profile_from_access_context(socket) do
    profile =
      case socket.assigns[:access_context] do
        %AccessContext{principal: {:human, account}} -> member_for_account(account)
        _anonymous -> nil
      end

    assign(socket, :current_profile, profile)
  end

  # Standalone embedded LiveViews (live_render children without Live.Session).
  defp mount_standalone(socket, session, mode) do
    if connected?(socket) do
      handshake = get_connect_info(socket, :session) || session
      connected_standalone(socket, session, handshake, lapsed(mode))
    else
      profile = disconnected_profile(session)

      {:cont,
       socket
       |> assign(:current_profile, profile)
       |> assign(:signed_out_reason, if(profile, do: nil, else: :signed_out))
       |> assign(:session_lease, nil)}
    end
  end

  defp primary_wallet(account) do
    candidates =
      [Map.get(account, :wallet_address) | List.wrap(Map.get(account, :wallet_addresses))]
      |> Enum.filter(&is_binary/1)
      |> Enum.map(&(&1 |> String.trim() |> String.downcase()))

    Enum.find(candidates, &Regex.match?(@wallet_pattern, &1))
  end

  defp provision_member(_privy_did, nil, _account), do: nil

  defp provision_member(privy_did, wallet, account) do
    if Regents.read_only?() do
      nil
    else
      case Members.upsert_from_privy(
             %{privy_user_id: privy_did, wallet_address: wallet},
             actor: %{role: :system}
           ) do
        {:ok, %Member{} = member} -> attach_account_wallets(member, account)
        _other -> nil
      end
    end
  end

  defp attach_account_wallets(member, account) do
    wallets =
      (Map.get(account, :wallet_addresses) || List.wrap(Map.get(account, :wallet_address)))
      |> Enum.filter(&is_binary/1)
      |> Enum.map(&String.downcase/1)
      |> Enum.uniq()

    %{member | wallet_addresses: wallets}
  end

  defp component_profile(%{assigns: %{lease: nil}}), do: :signed_out
  defp component_profile(%{assigns: %{lease: lease}}), do: resolve_component_lease(lease)
  defp component_profile(%{assigns: %{session_lease: nil}}), do: :signed_out
  defp component_profile(%{assigns: %{session_lease: lease}}), do: resolve_component_lease(lease)
  defp component_profile(_socket), do: :signed_out

  defp resolve_component_lease(lease) do
    case leased_profile(lease) do
      nil ->
        send(self(), {__MODULE__, :component_lease_lapsed})
        :lapsed

      profile ->
        profile
    end
  end

  defp take(socket, _take_profile, :signed_out), do: socket
  defp take(socket, take_profile, profile), do: take_profile.(socket, profile)

  defp connected_standalone(socket, static_session, handshake, lapsed) do
    case SessionAuthority.claim(handshake) do
      nil -> {:cont, signed_out(socket, SessionAuthority.claim_shaped?(handshake))}
      claim -> admit(socket, static_session, claim, lapsed)
    end
  end

  defp admit(socket, static_session, %{lineage: lineage} = claim, lapsed) do
    case SessionAuthority.resolve(claim) do
      {nil, nil} ->
        {:cont, signed_out(socket, true)}

      {^lineage, account} ->
        profile = member_for_account(account)

        if static_session["render_topic"] == SessionAuthority.topic(lineage) or
             is_nil(static_session["render_topic"]),
           do: {:cont, hold(socket, lineage, account, profile, lapsed)},
           else: {:halt, redirect(socket, to: static_session["render_route"] || @public_root)}
    end
  end

  defp hold(socket, _lineage, _account, nil, _lapsed),
    do: signed_out(socket, false)

  defp hold(socket, lineage, account, profile, lapsed) do
    lease = lease(lineage, account, profile)

    socket
    |> assign(current_profile: profile, signed_out_reason: nil, session_lease: lease)
    |> recheck_navigation(lease)
    |> attach_hook(:current_profile_event, :handle_event, fn _event, _params, socket ->
      recheck(socket, lease, lapsed)
    end)
    |> attach_hook(:current_profile_info, :handle_info, fn
      {__MODULE__, :component_lease_lapsed}, socket ->
        {_cont_or_halt, socket} = recheck(socket, lease, lapsed)
        {:halt, socket}

      _message, socket ->
        recheck(socket, lease, lapsed)
    end)
    |> attach_hook(:current_profile_async, :handle_async, fn _name, _result, socket ->
      recheck(socket, lease, lapsed)
    end)
  end

  defp signed_out(socket, ended?) do
    assign(socket,
      current_profile: nil,
      signed_out_reason: if(ended?, do: :expired, else: :signed_out),
      session_lease: nil
    )
  end

  defp lease(lineage, account, profile),
    do: %{lineage: lineage, account_id: account.id, profile_id: profile.id}

  defp lapsed(:default), do: &redirect(&1, to: @public_root)
  defp lapsed(:account), do: & &1

  defp recheck_navigation(%{router: nil} = socket, _lease), do: socket

  defp recheck_navigation(socket, lease) do
    socket
    |> assign(initial_params?: true)
    |> attach_hook(:current_profile_params, :handle_params, fn
      _params, _uri, %{assigns: %{initial_params?: true}} = socket ->
        {:cont, assign(socket, initial_params?: false)}

      _params, _uri, socket ->
        recheck(socket, lease, &redirect(&1, to: @public_root))
    end)
  end

  defp recheck(socket, lease, lapsed) do
    case leased_profile(lease) do
      nil ->
        {:halt, socket |> assign(current_profile: nil, signed_out_reason: :expired) |> lapsed.()}

      profile ->
        {:cont, assign(socket, :current_profile, profile)}
    end
  end

  defp rendered_topic(nil), do: %{}
  defp rendered_topic(lineage), do: %{"render_topic" => SessionAuthority.topic(lineage)}

  defp local_route(path, ""), do: path
  defp local_route(path, query), do: path <> "?" <> query
end
