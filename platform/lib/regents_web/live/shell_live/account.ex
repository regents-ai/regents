defmodule RegentsWeb.ShellLive.Account do
  @moduledoc """
  The Account pages, as ash-template has them: Account (the shared layout, whose
  agents list and pairing box are their own components), Credits (the account's
  Credits history and what each paired agent may spend of them), Wallets (read from the sign-in) and Connections (the accounts
  connected to it). Every read here is the account's own, made with what its
  sign-in verified, so nothing the browser sends can widen it. Agent changes from
  other tabs and sites reach the account menu's agents on every page, and the
  Account page's list and pairing box while it is open.
  """

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [connected?: 1, push_event: 3, send_update: 2]

  alias RegentAgents.Person
  alias Regents.{Accounts, Ens}
  alias Regents.Accounts.LinkedIdentity.Providers
  alias Regents.Actors.Human
  alias RegentsWeb.{AgentsPanel, CreditsHistoryLive, MenuAgents, PairingBox, Read}
  alias RegentsWeb.ShellLive.Identity

  @actions %{"link" => :link, "unlink" => :unlink}
  @refused %{
    tone: :error,
    message: "That connection couldn’t be updated. Refresh the page and try again."
  }

  @events ~w(request_verified_connection refresh_verified_connections public_name_saved credits_history_older)

  def handles?(event), do: event in @events

  def init(socket) do
    socket
    |> assign(
      verified_connections: %Read{},
      verified_connections_notice: nil,
      connection_outcome: nil,
      credits_history: %Read{},
      spending_agents: %Read{}
    )
    |> follow_agents()
  end

  def route(socket, route_spec) do
    socket
    |> refresh_ens(route_spec)
    |> load_credits_history(route_spec)
    |> load_spending_agents(route_spec)
    |> load_verified_connections(route_spec)
  end

  # Agents pair, check in and change from other tabs and other Regent sites. The
  # account menu's agents are on every page, so every signed-in page follows
  # them. Signing in or out reloads the page, so the person followed is the
  # page's own for as long as it is open.
  defp follow_agents(socket) do
    with true <- connected?(socket),
         %{privy_user_id: id} <- Identity.current_account(socket.assigns.access_context) do
      Phoenix.PubSub.subscribe(Regents.PubSub, RegentAgents.topic(id))
    end

    socket
  end

  def handle_event(
        "request_verified_connection",
        %{"action" => action, "provider" => provider},
        socket
      ) do
    with %Human{} <- Identity.human_actor(socket),
         {:ok, provider} <- Providers.parse(provider),
         {:ok, action} <- Map.fetch(@actions, action),
         {:ok, request} <-
           identity_request(action, provider, socket.assigns.verified_connections.value) do
      socket
      |> assign(verified_connections_notice: %{tone: :info, message: connection_started(request)})
      |> push_event("verified-connections:request", request)
    else
      _refused -> assign(socket, verified_connections_notice: @refused)
    end
  end

  # The outcome is judged against the connections read after the provider came back.
  def handle_event("refresh_verified_connections", params, socket) do
    socket
    |> assign(connection_outcome: params, verified_connections_notice: nil)
    |> read_verified_connections()
    |> report_connection_outcome()
  end

  # The Account page saved the person's name in the shared profile. Every event
  # reads the account again first (`RegentsWeb.Live.Session`), so the page
  # already shows the new name everywhere it appears.
  def handle_event("public_name_saved", _params, socket), do: socket

  def handle_event("credits_history_older", _params, socket) do
    with %Read{value: %{more?: true} = history} <- socket.assigns.credits_history,
         account when account != nil <- Identity.current_account(socket.assigns.access_context) do
      actor = Regents.Credits.person(account)

      Read.now(socket, :credits_history, account.privy_user_id, fn ->
        CreditsHistoryLive.older(history, &RegentCredits.history(&1, actor: actor))
      end)
    else
      _no_more -> socket
    end
  end

  def handle_event(_event, _params, socket), do: socket

  @doc """
  An agent paired, checked in or was unpaired, here or on another Regent site.
  The account menu's agents are on every page; the Account page also lists the
  agents and holds the pairing box, and the Credits page lists what each may spend.
  """
  def agents_changed(socket) do
    send_update(MenuAgents, id: "shell-agents", agents_changed: true)

    if socket.assigns.route_spec.route_id == :account do
      send_update(AgentsPanel, id: "account-agents", agents_changed: true)
      send_update(PairingBox, id: "account-pairing-box", agents_changed: true)
    end

    load_spending_agents(socket, socket.assigns.route_spec)
  end

  @doc "The balance changed on this or any Regent site; the Credits history follows."
  def credits_changed(socket), do: load_credits_history(socket, socket.assigns.route_spec)

  # Sign-in read the wallet's primary name once. A wallet never answered for, or
  # last answered for more than a day ago, is asked again when the Account page
  # opens; the session reads the account again once the answer is recorded, so
  # every place showing the name follows. Only the connected page asks, so the
  # static render does not start a lookup the connected mount would start again.
  defp refresh_ens(socket, %{route_id: :account}) do
    with true <- connected?(socket),
         %{wallet_address: wallet, ens_identity: identity} = account when is_binary(wallet) <-
           Identity.current_account(socket.assigns.access_context),
         true <- is_nil(identity) or ens_stale?(identity) do
      Ens.refresh(account)
    end

    socket
  end

  defp refresh_ens(socket, _route_spec), do: socket

  defp ens_stale?(%{updated_at: read_at}),
    do: DateTime.diff(DateTime.utc_now(), read_at, :hour) >= 24

  # The newest page of the account's Credits history, read again on each
  # change with the older pages already shown kept below it.
  defp load_credits_history(socket, %{route_id: :credits}) do
    case Identity.current_account(socket.assigns.access_context) do
      nil ->
        Read.clear(socket, :credits_history)

      account ->
        actor = Regents.Credits.person(account)
        shown = shown_history(socket.assigns.credits_history, account)

        Read.now(socket, :credits_history, account.privy_user_id, fn ->
          newest_history(actor, shown)
        end)
    end
  end

  defp load_credits_history(socket, _route_spec), do: Read.clear(socket, :credits_history)

  defp newest_history(actor, shown) do
    with {:ok, page} <- RegentCredits.history(%{}, actor: actor),
         do: {:ok, CreditsHistoryLive.refreshed(page, shown)}
  end

  defp shown_history(%Read{owner: owner, value: %{} = history}, %{privy_user_id: owner}),
    do: history

  defp shown_history(_read, _account), do: nil

  # The Credits page sets what each paired agent may spend, so it reads the agents
  # paired now; one unpaired since is gone from the list.
  defp load_spending_agents(socket, %{route_id: :credits}) do
    case agent_person(socket) do
      %Person{privy_user_id: id} = person ->
        Read.now(socket, :spending_agents, id, fn ->
          RegentAgents.list_my_agents(actor: person)
        end)

      nil ->
        Read.clear(socket, :spending_agents)
    end
  end

  defp load_spending_agents(socket, _route_spec), do: Read.clear(socket, :spending_agents)

  defp load_verified_connections(socket, %{route_id: :connections}),
    do: read_verified_connections(socket)

  defp load_verified_connections(socket, _route_spec) do
    socket
    |> Read.clear(:verified_connections)
    |> assign(verified_connections_notice: nil, connection_outcome: nil)
  end

  # The account's own record is the only thing a connection is read from, so
  # nothing the browser reports can name a connection the record does not hold.
  defp read_verified_connections(socket) do
    case Identity.human_actor(socket) do
      %Human{} = actor ->
        Read.now(socket, :verified_connections, actor.human_account_id, fn ->
          Accounts.list_my_linked_identities(actor: actor)
        end)

      nil ->
        Read.clear(socket, :verified_connections)
    end
  end

  defp identity_request(:link, provider, _identities),
    do: {:ok, %{action: :link, provider: provider}}

  defp identity_request(:unlink, provider, identities) when is_list(identities) do
    case Enum.find(identities, &(&1.provider == provider)) do
      nil -> :error
      identity -> {:ok, %{action: :unlink, provider: provider, subject: identity.subject}}
    end
  end

  defp identity_request(_action, _provider, _identities), do: :error

  # X and GitHub take the whole tab to their own approval page and bring it
  # back; Farcaster asks for a scan here.
  defp connection_started(%{action: :link, provider: :farcaster}),
    do: "Scan the code with Farcaster to approve the connection."

  defp connection_started(%{action: :link, provider: provider}),
    do: "Taking you to #{Providers.label(provider)} to approve the connection."

  defp connection_started(%{action: :unlink, provider: provider}),
    do: "Disconnecting #{Providers.label(provider)}…"

  defp report_connection_outcome(%{assigns: %{connection_outcome: nil}} = socket), do: socket

  defp report_connection_outcome(%{assigns: assigns} = socket) do
    notice = connection_outcome(assigns.connection_outcome, assigns.verified_connections)
    assign(socket, verified_connections_notice: notice, connection_outcome: nil)
  end

  defp connection_outcome(%{"error" => "already-connected"}, _read),
    do: %{tone: :error, message: "That account is already connected to another account here."}

  defp connection_outcome(%{"error" => error}, _read) when is_binary(error) and error != "",
    do: %{tone: :error, message: "That connection couldn’t be verified. Try again."}

  defp connection_outcome(params, %Read{state: state, value: identities})
       when state in [:ready, :empty] do
    with {:ok, provider} <- Providers.parse(params["provider"]),
         {:ok, action} <- Map.fetch(@actions, params["action"]) do
      label = Providers.label(provider)

      case {action, Enum.any?(identities, &(&1.provider == provider))} do
        {:link, true} ->
          %{tone: :success, message: "#{label} connected."}

        {:link, false} ->
          %{tone: :error, message: "#{label} didn’t come back connected. Try again."}

        {:unlink, false} ->
          %{tone: :success, message: "#{label} disconnected."}

        {:unlink, true} ->
          %{tone: :error, message: "#{label} is still connected. Try again."}
      end
    else
      :error -> nil
    end
  end

  defp connection_outcome(_params, _read), do: nil

  # Pairings name the person by their Privy user ID, the same on every site.
  @doc false
  def agent_person(socket) do
    case Identity.current_account(socket.assigns.access_context) do
      %{privy_user_id: id} -> %Person{privy_user_id: id}
      nil -> nil
    end
  end
end
