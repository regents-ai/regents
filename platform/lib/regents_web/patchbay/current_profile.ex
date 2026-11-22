defmodule RegentsWeb.Patchbay.CurrentProfile do
  @moduledoc """
  Bridges Regents' signed-in `HumanAccount` session (`SessionAuthority`) to
  Patchbay's `Regents.Patchbay.Members.Member` profile for Patchbay LiveViews
  and controllers.
  """

  import Phoenix.Component, only: [assign: 2, assign: 3, assign_new: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1, redirect: 2]

  alias Regents.Account.Accounts.SessionAuthority
  alias Regents.Patchbay.Members
  alias Regents.Patchbay.Members.Member
  alias RegentsWeb.VisitLog

  @public_root "/patchbay"

  def render_context(conn) do
    conn
    |> VisitLog.session()
    |> Map.merge(rendered_topic(conn.assigns[:current_lineage]))
    |> Map.put("render_route", local_route(conn.request_path, conn.query_string))
  end

  def on_mount(mode, _params, session, socket) when mode in [:default, :account] do
    if connected?(socket) do
      connected(socket, session, lapsed(mode))
    else
      {:cont,
       socket
       |> assign_new(:current_profile, fn -> nil end)
       |> assign_new(:signed_out_reason, fn -> :signed_out end)
       |> assign(:session_lease, nil)}
    end
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
  end

  def leased_profile(nil), do: nil

  def leased_profile(%{lineage: lineage, account_id: account_id}) do
    case SessionAuthority.leased_account(lineage, account_id) do
      %{} = account -> member_for_account(account)
      nil -> nil
    end
  end

  def leased_profile(_other), do: nil

  @doc "Finds or provisions the active Patchbay member for a signed-in Regents account."
  @spec member_for_account(map() | nil) :: Member.t() | nil
  def member_for_account(nil), do: nil

  def member_for_account(%{privy_did: privy_did, wallet_address: wallet} = account)
      when is_binary(privy_did) do
    case Members.get_profile_by_privy_user_id(privy_did) do
      {:ok, %Member{} = member} ->
        attach_account_wallets(member, account)

      {:ok, nil} ->
        provision_member(privy_did, wallet, account)

      _other ->
        nil
    end
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

  defp provision_member(_privy_did, wallet, _account)
       when not is_binary(wallet) or wallet == "",
       do: nil

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
    wallets = Map.get(account, :wallet_addresses) || List.wrap(account.wallet_address)
    %{member | wallet_addresses: wallets}
  end

  defp component_profile(%{assigns: %{lease: nil}}), do: :signed_out

  defp component_profile(%{assigns: %{lease: lease}}) do
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

  defp connected(socket, session, lapsed) do
    case SessionAuthority.claim(session) do
      nil -> {:cont, signed_out(socket, SessionAuthority.claim_shaped?(session))}
      claim -> admit(socket, session, claim, lapsed)
    end
  end

  defp admit(socket, session, %{lineage: lineage} = claim, lapsed) do
    case SessionAuthority.resolve(claim) do
      {nil, nil} ->
        {:cont, signed_out(socket, true)}

      {^lineage, account} ->
        profile = member_for_account(account)

        if session["render_topic"] == SessionAuthority.topic(lineage) or
             is_nil(session["render_topic"]),
           do: {:cont, hold(socket, lineage, account, profile, lapsed)},
           else: {:halt, redirect(socket, to: session["render_route"] || @public_root)}
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
