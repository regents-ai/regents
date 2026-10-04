defmodule RegentsWeb.ShellLive.Account do
  @moduledoc """
  The Account page: the wallet's primary name, verified connections, the names
  the signed-in wallets hold and may still claim, and paired agents. Every read
  here is the account's own, made with the wallets its sign-in verified, so
  nothing the browser sends can widen it. Agent changes from other tabs are
  heard only while this page is open.
  """

  import Phoenix.Component, only: [assign: 2]

  import Phoenix.LiveView,
    only: [connected?: 1, put_flash: 3, push_event: 3, start_async: 3, stream: 3, stream: 4]

  alias RegentAgents.{Harness, PairedAgent, PairingCode, Person}
  alias Regents.{Accounts, AgentActivity, Ens, Names}
  alias Regents.Accounts.LinkedIdentity.Providers
  alias Regents.Actors.Human
  alias RegentsWeb.EventInput
  alias RegentsWeb.ShellLive.Identity

  @identity_providers %{"x" => :x, "github" => :github, "farcaster" => :farcaster}
  @names_page_size 50
  @blank_claim_name %{value: "", problems: [], availability: nil}
  @page_events ~w(load_more_names check_claim_name claim_name issue_pairing_code open_agent change_agent_harness unpair_agent)
  # Far longer than any name a person claims; the name's own rules say what is too long.
  @claim_name_limit 255

  @events @page_events ++
            ~w(request_verified_connection refresh_verified_connections close_agent)

  def handles?(event), do: event in @events

  def init(socket) do
    socket
    |> stream(:account_names, [])
    |> assign(agents_topic: nil, agents_now: DateTime.utc_now())
    |> cleared()
  end

  def route(socket, %{route_id: :account}) do
    socket
    |> follow_agents()
    |> load_ens()
    |> reload_verified_connections()
    |> load_names()
    |> load_claims()
    |> load_paired_agents()
  end

  def route(socket, _route_spec), do: socket |> unfollow_agents() |> cleared()

  defp cleared(socket) do
    assign(socket,
      account_ens: nil,
      account_names: nil,
      account_claims: nil,
      account_claim_name: @blank_claim_name,
      verified_connections: [],
      verified_connections_notice: nil,
      paired_agents: nil,
      agent_pairing: nil,
      agent_detail: nil,
      agent_notice: nil
    )
  end

  # Agents pair, check in and change from other tabs; only this page shows them.
  defp follow_agents(%{assigns: %{agents_topic: nil}} = socket) do
    with true <- connected?(socket),
         %Person{privy_user_id: id} <- agent_person(socket) do
      topic = RegentAgents.topic(id)
      Phoenix.PubSub.subscribe(Regents.PubSub, topic)
      assign(socket, agents_topic: topic)
    else
      _not_followed -> socket
    end
  end

  defp follow_agents(socket), do: socket

  defp unfollow_agents(%{assigns: %{agents_topic: nil}} = socket), do: socket

  defp unfollow_agents(socket) do
    Phoenix.PubSub.unsubscribe(Regents.PubSub, socket.assigns.agents_topic)
    assign(socket, agents_topic: nil)
  end

  def handle_event(
        "request_verified_connection",
        %{"action" => action, "provider" => provider},
        socket
      ) do
    with %Human{} <- Identity.human_actor(socket),
         {:ok, provider} <- linked_identity_provider(provider),
         {:ok, request} <- identity_request(action, provider, socket.assigns.verified_connections) do
      socket
      |> assign(verified_connections_notice: %{tone: :info, message: connection_started(request)})
      |> push_event("verified-connections:request", request)
    else
      _error ->
        assign(socket,
          verified_connections_notice: %{
            tone: :error,
            message: "That connection couldn’t be updated. Refresh the page and try again."
          }
        )
    end
  end

  # The browser only reports how its side ended. Whether the connection really
  # landed is read from the account's own record, so the page never says
  # "connected" on the browser's word alone.
  def handle_event("refresh_verified_connections", params, socket) do
    socket = reload_verified_connections(socket)

    notice =
      with {:ok, provider} <- linked_identity_provider(params["provider"]),
           {:ok, action} <- identity_action(params["action"]) do
        connection_outcome(params["error"], action, provider, socket.assigns.verified_connections)
      else
        _unknown_outcome -> connection_outcome(params["error"])
      end

    assign(socket, verified_connections_notice: notice)
  end

  def handle_event("close_agent", _params, socket),
    do: assign(socket, agent_detail: nil, agent_notice: nil)

  # An event from a page that has since moved on changes nothing.
  def handle_event(event, _params, %{assigns: %{route_spec: %{route_id: route_id}}} = socket)
      when event in @page_events and route_id != :account,
      do: socket

  def handle_event("load_more_names", _params, socket), do: load_more_names(socket)

  def handle_event("check_claim_name", %{"name" => name}, socket)
      when is_binary(name) and byte_size(name) <= @claim_name_limit,
      do: assign(socket, account_claim_name: check_claim_name(socket, name))

  def handle_event("claim_name", %{"name" => name}, socket)
      when is_binary(name) and byte_size(name) <= @claim_name_limit,
      do: claim_name(socket, name)

  def handle_event("issue_pairing_code", _params, socket),
    do: assign(socket, agent_pairing: issue_pairing_code(socket), agent_notice: nil)

  def handle_event("open_agent", %{"id" => id}, socket) when is_binary(id),
    do: socket |> assign(agent_notice: nil) |> show_agent(id, agent_person(socket))

  def handle_event("change_agent_harness", %{"agent" => id, "harness" => harness}, socket)
      when is_binary(id) and is_binary(harness) do
    actor = agent_person(socket)

    result =
      with {:ok, agent} <- my_agent(id, actor),
           {:ok, changed} <- RegentAgents.change_agent_harness(agent, harness, actor: actor),
           do: {:ok, {:change_harness, changed}}

    agent_edited(socket, actor, result)
  end

  def handle_event("unpair_agent", %{"id" => id}, socket) when is_binary(id) do
    actor = agent_person(socket)

    result =
      with {:ok, agent} <- my_agent(id, actor),
           :ok <- RegentAgents.unpair_agent(agent, actor: actor),
           do: {:ok, {:unpair, agent}}

    agent_edited(socket, actor, result)
  end

  def handle_event(_event, _params, socket),
    do: put_flash(socket, :error, EventInput.unreadable())

  @doc """
  What the open agent has done and its registry listing, landing only while
  that agent is still open.
  """
  def settle_activity(
        %{assigns: %{agent_detail: %{agent: %{id: id}} = detail}} = socket,
        {:agent_activity, id},
        result
      ) do
    {activity, listing} =
      case result do
        {:ok, {:ok, %{entries: entries, listing: listing}}} -> {entries, listing}
        _failed -> {:unavailable, detail.listing}
      end

    assign(socket, agent_detail: %{detail | activity: activity, listing: listing})
  end

  def settle_activity(socket, _name, _result), do: socket

  @doc """
  The session has already re-read the account by the time this arrives, so
  what the chain answered is on the socket; only this page reports whether the
  check found anything to record.
  """
  def ens_finished(%{assigns: %{route_spec: %{route_id: :account}}} = socket) do
    case Identity.current_account(socket.assigns.access_context) do
      %{ens_identity: %{}} -> assign(socket, account_ens: :ready)
      _unanswered -> assign(socket, account_ens: :unavailable)
    end
  end

  def ens_finished(socket), do: socket

  @doc "An agent paired, checked in, or was changed from another tab."
  def agents_changed(%{assigns: %{route_spec: %{route_id: :account}}} = socket),
    do: reload_paired_agents(socket, agent_person(socket))

  def agents_changed(socket), do: socket

  # Sign-in read the wallet's primary name once. A wallet never answered for, or
  # last answered for more than a day ago, is asked again when its own page
  # opens, and the page takes the answer as it lands. Only the connected page
  # asks, so the static render does not start a lookup the connected mount
  # would start again a moment later.
  defp load_ens(socket) do
    case Identity.current_account(socket.assigns.access_context) do
      %{wallet_address: nil} ->
        assign(socket, account_ens: :ready)

      %{ens_identity: nil} = account ->
        assign(socket, account_ens: check_ens(socket, account))

      %{ens_identity: identity} = account ->
        if ens_stale?(identity), do: check_ens(socket, account)
        assign(socket, account_ens: :ready)

      nil ->
        assign(socket, account_ens: nil)
    end
  end

  defp check_ens(socket, account) do
    if connected?(socket) do
      case Ens.refresh(account) do
        :started -> :checking
        :unconfigured -> :unavailable
      end
    else
      :checking
    end
  end

  defp ens_stale?(%{updated_at: read_at}),
    do: DateTime.diff(DateTime.utc_now(), read_at, :hour) >= 24

  defp reload_verified_connections(socket) do
    case Identity.human_actor(socket) do
      %Human{} = actor ->
        case Accounts.list_my_linked_identities(actor: actor) do
          {:ok, identities} -> assign(socket, verified_connections: identities)
          {:error, _error} -> assign(socket, verified_connections: [])
        end

      nil ->
        assign(socket, verified_connections: [])
    end
  end

  defp linked_identity_provider(provider) do
    case Map.fetch(@identity_providers, provider) do
      {:ok, provider} -> {:ok, provider}
      :error -> {:error, :invalid_provider}
    end
  end

  defp identity_request("link", provider, _identities) do
    {:ok, %{action: :link, provider: provider}}
  end

  defp identity_request("unlink", provider, identities) do
    case Enum.find(identities, &(&1.provider == provider)) do
      nil -> {:error, :not_connected}
      identity -> {:ok, %{action: :unlink, provider: provider, subject: identity.subject}}
    end
  end

  defp identity_request(_action, _provider, _identities), do: {:error, :invalid_action}

  defp identity_action("link"), do: {:ok, :link}
  defp identity_action("unlink"), do: {:ok, :unlink}
  defp identity_action(_action), do: {:error, :invalid_action}

  # X and GitHub take the whole tab to their own approval page and bring it
  # back; Farcaster asks for a scan here.
  defp connection_started(%{action: :link, provider: :farcaster}),
    do: "Scan the code with Farcaster to approve the connection."

  defp connection_started(%{action: :link, provider: provider}),
    do: "Taking you to #{Providers.label(provider)} to approve the connection."

  defp connection_started(%{action: :unlink, provider: provider}),
    do: "Disconnecting #{Providers.label(provider)}…"

  defp connection_outcome("already-connected"),
    do: %{tone: :error, message: "That account is already connected to another Regent account."}

  defp connection_outcome(error) when is_binary(error) and error != "",
    do: %{tone: :error, message: "That connection couldn’t be verified. Try again."}

  defp connection_outcome(_none), do: nil

  defp connection_outcome(error, _action, _provider, _identities)
       when is_binary(error) and error != "",
       do: connection_outcome(error)

  defp connection_outcome(_none, action, provider, identities) do
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
  end

  # The list is oldest first and grows a page at a time as the reader reaches
  # its end. The rows go to the browser and only the place to continue from is
  # kept here; a page that cannot be read leaves the rows already shown in place.
  defp load_names(socket) do
    case Identity.human_actor(socket) do
      %Human{wallet_addresses: []} ->
        first_names_page(socket, %{results: [], more?: false})

      %Human{} = actor ->
        case Names.list_my_claims(actor: actor, page: [limit: @names_page_size]) do
          {:ok, page} -> first_names_page(socket, page)
          {:error, _error} -> assign(socket, account_names: :unavailable)
        end

      nil ->
        assign(socket, account_names: nil)
    end
  end

  defp first_names_page(socket, page) do
    socket
    |> stream(:account_names, page.results, reset: true)
    |> assign(
      account_names: %{
        empty?: page.results == [],
        more?: page.more?,
        cursor: names_cursor(page.results),
        stalled?: false
      }
    )
  end

  defp load_more_names(%{assigns: %{account_names: %{more?: true} = names}} = socket) do
    case Names.list_my_claims(
           actor: Identity.human_actor(socket),
           page: [limit: @names_page_size, after: names.cursor]
         ) do
      {:ok, page} ->
        socket
        |> stream(:account_names, page.results)
        |> assign(account_names: %{names | more?: page.more?, cursor: names_cursor(page.results)})

      {:error, _error} ->
        assign(socket, account_names: %{names | more?: false, stalled?: true})
    end
  end

  defp load_more_names(socket), do: socket

  defp names_cursor([]), do: nil
  defp names_cursor(claims), do: List.last(claims).__metadata__.keyset

  # The claims the signed-in wallets may still make, read the same way as the
  # names they hold. A read that fails is shown as unanswered, never as none.
  defp load_claims(socket) do
    claims =
      case Identity.human_actor(socket) do
        %Human{wallet_addresses: []} -> %{free: 0, paid: 0}
        %Human{} = actor -> claims_available(actor)
        nil -> nil
      end

    assign(socket, account_claims: claims, account_claim_name: @blank_claim_name)
  end

  defp claims_available(actor) do
    case Names.claims_available(actor: actor) do
      {:ok, claims} -> claims
      {:error, _error} -> :unavailable
    end
  end

  # A name is judged as it is typed: the rules first, then whether a recorded
  # claim already holds it. The claim itself is not made here.
  defp check_claim_name(_socket, ""), do: @blank_claim_name

  defp check_claim_name(socket, name) do
    case Names.label_problems(name) do
      [] -> %{value: name, problems: [], availability: label_availability(socket, name)}
      problems -> %{value: name, problems: problems, availability: nil}
    end
  end

  # The claim is made by the account's own sign-in and judged again where it
  # is recorded, whatever the page showed. Afterwards everything the claim
  # could have changed is read again, so a refusal is explained by what is
  # true now: the name taken, or no free claim left.
  defp claim_name(socket, name) do
    with %Human{} = actor <- Identity.human_actor(socket),
         {:ok, claim} <- Names.claim_free_name(name, actor: actor) do
      socket
      |> load_names()
      |> load_claims()
      |> assign(
        account_claim_name: %{@blank_claim_name | availability: {:claimed_now, claim.ens_fqdn}}
      )
    else
      nil ->
        socket

      {:error, _error} ->
        socket
        |> load_claims()
        |> then(&assign(&1, account_claim_name: refused_claim_name(&1, name)))
    end
  end

  defp refused_claim_name(socket, name) do
    case {check_claim_name(socket, name), socket.assigns.account_claims} do
      {%{availability: :available} = claim_name, %{free: free}} when free > 0 ->
        %{claim_name | availability: :not_claimed}

      {claim_name, _claims} ->
        claim_name
    end
  end

  defp label_availability(socket, name) do
    case Names.label_claimed?(name, actor: Identity.human_actor(socket)) do
      {:ok, true} -> :claimed
      {:ok, false} -> :available
      {:error, _error} -> :unavailable
    end
  end

  defp load_paired_agents(socket) do
    case agent_person(socket) do
      %Person{} = actor ->
        reload_paired_agents(socket, actor)

      nil ->
        assign(socket,
          paired_agents: nil,
          agent_pairing: nil,
          agent_detail: nil,
          agent_notice: nil
        )
    end
  end

  # The open agent is read again with the list, so its dialog closes on its own
  # once the agent is unpaired.
  defp reload_paired_agents(socket, actor) do
    agents =
      case RegentAgents.list_my_agents(actor: actor) do
        {:ok, agents} -> agents
        {:error, _error} -> :unavailable
      end

    socket =
      assign(socket,
        paired_agents: agents,
        agents_now: DateTime.utc_now(),
        agent_pairing: pairing_after(socket.assigns.agent_pairing, agents)
      )

    case socket.assigns.agent_detail do
      %{agent: %{id: id}} -> show_agent(socket, id, actor)
      nil -> socket
    end
  end

  # A code on screen gives way to the agent that used it, so a spent code is
  # never left there to send again.
  defp pairing_after(%PairingCode.Issued{issued_at: issued_at} = shown, agents)
       when is_list(agents) do
    case Enum.find(agents, &(DateTime.compare(&1.paired_at, issued_at) != :lt)) do
      nil -> shown
      agent -> {:paired, agent}
    end
  end

  defp pairing_after(shown, _agents), do: shown

  # What the agent has done, and its registry listing, are read from the
  # sign-in service in the background. What is already on screen for this agent
  # stays until the new reading lands.
  defp show_agent(socket, id, actor) do
    case RegentAgents.get_my_agent(id, actor: actor) do
      {:ok, %PairedAgent{} = agent} ->
        {activity, listing} =
          case socket.assigns.agent_detail do
            %{agent: %{id: ^id}, activity: shown, listing: listing} -> {shown, listing}
            _other -> {:loading, nil}
          end

        socket
        |> assign(agent_detail: %{agent: agent, activity: activity, listing: listing})
        |> start_async({:agent_activity, id}, fn -> AgentActivity.recent(agent) end)

      _missing ->
        assign(socket, agent_detail: nil)
    end
  end

  # Pairings name the person by their Privy user ID, the same on every site.
  defp agent_person(socket) do
    case Identity.current_account(socket.assigns.access_context) do
      %{privy_user_id: id} -> %Person{privy_user_id: id}
      nil -> nil
    end
  end

  defp my_agent(id, actor) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         {:ok, %PairedAgent{} = agent} <- RegentAgents.get_my_agent(id, actor: actor) do
      {:ok, agent}
    else
      {:error, error} -> {:error, error}
      _missing -> {:error, :not_found}
    end
  end

  # Every agent edit says how it ended, and the list is read again either way,
  # so what is shown is the account's record and not the click.
  defp agent_edited(socket, actor, result) do
    socket
    |> reload_paired_agents(actor)
    |> assign(agent_notice: agent_notice(result))
  end

  defp agent_notice({:ok, {:change_harness, agent}}),
    do: {:status, "Saved. #{agent.name} runs on #{Harness.label(agent.harness)}."}

  defp agent_notice({:ok, {:unpair, agent}}),
    do: {:status, "#{agent.name} is unpaired. It will need a new code to pair again."}

  defp agent_notice({:error, :not_found}),
    do: {:alert, "This agent is no longer paired with your account. Nothing changed."}

  defp agent_notice({:error, %Ash.Error.Invalid{}}),
    do: {:alert, "Choose what it runs on from the list. Nothing changed."}

  defp agent_notice({:error, _unavailable}),
    do: {:alert, "Your agents couldn’t be updated just now. Nothing changed. Try again."}

  # A code already on screen stays there while a new one can't be made yet.
  defp issue_pairing_code(socket) do
    case RegentAgents.issue_pairing_code(actor: agent_person(socket)) do
      {:ok, issued} ->
        issued

      {:error,
       %Ash.Error.Invalid{errors: [%Ash.Error.Invalid.Unavailable{reason: :issued_recently}]}} ->
        case socket.assigns.agent_pairing do
          %PairingCode.Issued{} = shown -> shown
          _none -> :wait
        end

      {:error, _error} ->
        :unavailable
    end
  end
end
