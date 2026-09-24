defmodule AshPlatformWeb.ShellLive do
  use AshPlatformWeb, :live_view

  import AshPlatformWeb.Components.Shell
  import AshPlatformWeb.RedeemLive
  import AshPlatformWeb.StakeLive

  alias AshPlatform.{
    Accounts,
    Ens,
    Formation,
    Names,
    OpenSea,
    Redemption,
    Staking
  }

  alias AshPlatform.Accounts.LinkedIdentity.Providers
  alias AshPlatform.Actors.Human
  alias AshPlatform.OpenSea.HoldingsCache
  alias AshPlatform.Staking.Facts, as: StakingFacts
  alias AshPlatform.Staking.SnapshotCache
  alias AshPlatform.WalletActions.Address
  alias AshPlatform.WalletActions.TransactionObserver
  alias AshPlatformWeb.AccountLive
  alias AshPlatformWeb.FormationLive
  alias AshPlatformWeb.ProductLive
  alias AshPlatformWeb.RedeemGalleryLive
  alias AshPlatformWeb.RegentOpsLive
  alias AshPlatformWeb.RegentProfileLive
  alias AshPlatformWeb.RouteCatalog

  @identity_providers %{"x" => :x, "github" => :github, "farcaster" => :farcaster}
  @staking_refresh_failure_notice "Refresh failed. The last confirmed Base snapshot remains on screen."
  # Names the budget it belongs to. The Redeem page has its own, unrelated
  # per-visitor limit on looking up owned NFTs, and the two refusals must never
  # read as the same thing.
  @shared_refresh_budget_notice "Contract data was refreshed for everyone moments ago. Ask for a new reading again in a few seconds."
  @redemption_preparation_failure_notice "That action could not be prepared. Check the wallet and selection."
  @max_wallet_observations 8
  @open_sea_lookup_window 60_000
  @default_open_sea_lookups_per_minute 6
  @names_page_size 50
  @blank_claim_name %{value: "", problems: [], availability: nil}

  @impl true
  def mount(params, session, socket) do
    route_spec = RouteCatalog.fetch!(socket.assigns.live_action, params)
    socket = assign(socket, :theme, session["theme"])

    if connected?(socket),
      do: Phoenix.PubSub.subscribe(AshPlatform.PubSub, SnapshotCache.topic())

    {:ok,
     socket
     |> stream(:account_names, [])
     |> assign(
       content_generation: 0,
       account_ens: nil,
       account_names: nil,
       account_claims: nil,
       account_claim_name: @blank_claim_name,
       verified_connections: [],
       verified_connections_notice: nil,
       route_params: params,
       regent: socket.assigns.current_regent,
       regent_status: if(socket.assigns.current_regent, do: :ready, else: :empty),
       redemption: nil,
       redemption_collection: "animata_i",
       redemption_token_id: "",
       redemption_notice: nil,
       redemption_read: nil,
       redemption_generation: 0,
       redemption_snapshot_selection: nil,
       redemption_wallet: nil,
       redemption_status: :loading,
       redemption_refresh_block: nil,
       owned_collectibles: %{status: :idle, animata: [], regents_club: []},
       owned_collectibles_limit: 24,
       open_sea_lookup: nil,
       open_sea_lookup_starts: [],
       staking: nil,
       staking_action: "stake",
       staking_amount: "",
       staking_wallet: nil,
       staking_notice: nil,
       staking_read: nil,
       staking_shared_reading: false,
       staking_status: :loading,
       wallet_reconnect: nil,
       route_spec: route_spec,
       shell_instance: System.unique_integer([:positive, :monotonic]),
       wallet_observations: MapSet.new()
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    route_spec = RouteCatalog.fetch!(socket.assigns.live_action, params)
    generation = socket.assigns.content_generation + 1

    socket =
      socket
      |> assign(content_generation: generation, route_spec: route_spec, route_params: params)
      |> load_regent_route(route_spec, params)
      |> load_account_ens(route_spec)
      |> load_verified_connections(route_spec)
      |> load_account_names(route_spec)
      |> load_account_claims(route_spec)

    cond do
      route_spec.route_id == :account ->
        {:noreply, socket}

      connected?(socket) ->
        {:noreply,
         socket
         |> maybe_start_staking(route_spec, generation)
         |> maybe_start_redemption(route_spec, generation)}

      true ->
        {:noreply, paint_initial_staking(socket, route_spec)}
    end
  end

  # A wallet reading answers for one account at its own block and says nothing
  # about the contract, so it is set beside the shared reading rather than over
  # it. With no shared reading on screen there is no dashboard to attach it to,
  # and the page keeps saying so.
  @impl true
  def handle_async(
        {:staking, generation} = name,
        {:ok, {generation, {:ok, wallet_facts}}},
        %{assigns: %{content_generation: generation, staking: staking}} = socket
      )
      when is_map(staking) do
    {:noreply,
     socket
     |> release_staking_read(name)
     |> assign(
       staking: StakingFacts.merge(staking, wallet_facts),
       staking_status: :ready,
       staking_notice: clear_staking_refresh_failure(socket.assigns.staking_notice)
     )}
  end

  # A failed or crashed wallet read says nothing about the contract reading
  # beside it, so that reading stays exactly where it is and only this wallet's
  # own figures are marked unavailable. The page keeps its layout and every
  # control on it.
  def handle_async(
        {:staking, generation} = name,
        {:ok, {generation, {:error, _reason}}},
        %{assigns: %{content_generation: generation}} = socket
      ) do
    {:noreply, socket |> release_staking_read(name) |> wallet_read_failed()}
  end

  def handle_async(
        {:staking, generation} = name,
        {:exit, _reason},
        %{assigns: %{content_generation: generation}} = socket
      ) do
    {:noreply, socket |> release_staking_read(name) |> wallet_read_failed()}
  end

  def handle_async({:staking, _generation} = name, _result, socket),
    do: {:noreply, release_staking_read(socket, name)}

  def handle_async(
        {:redemption, generation} = name,
        {:ok, {generation, {:ok, redemption}}},
        %{
          assigns: %{
            route_spec: %{route_id: :redeem},
            redemption_generation: generation
          }
        } = socket
      ) do
    read = socket.assigns.redemption_read

    refresh_block =
      case read do
        %{name: ^name, announce_refresh: true} -> redemption.block_number
        _ -> socket.assigns.redemption_refresh_block
      end

    {:noreply,
     socket
     |> release_redemption_read(name)
     |> assign(
       redemption: redemption,
       redemption_status: :ready,
       redemption_refresh_block: refresh_block,
       redemption_snapshot_selection: current_redemption_selection(socket.assigns)
     )
     |> maybe_start_open_sea_lookup(match?(%{name: ^name, lookup_owned: true}, read), generation)}
  end

  def handle_async(
        {:redemption, generation} = name,
        {:ok, {generation, {:error, reason}}},
        %{
          assigns: %{
            route_spec: %{route_id: :redeem},
            redemption_generation: generation
          }
        } = socket
      ) do
    {:noreply, socket |> release_redemption_read(name) |> redemption_read_failed(refusal(reason))}
  end

  # A crashed read answered nothing about Base. Release the refresh control and
  # preserve an existing snapshot; only an initial read has no data to retain.
  def handle_async(
        {:redemption, generation} = name,
        {:exit, _reason},
        %{
          assigns: %{
            route_spec: %{route_id: :redeem},
            redemption_generation: generation
          }
        } = socket
      ) do
    {:noreply, socket |> release_redemption_read(name) |> redemption_read_failed(:unavailable)}
  end

  # A read whose page has since moved on still releases its own marker, so the
  # refresh control is never left disabled by a read nobody is waiting for.
  def handle_async({:redemption, _generation} = name, _result, socket),
    do: {:noreply, release_redemption_read(socket, name)}

  def handle_async(
        {:open_sea, wallet} = name,
        {:ok, {:ok, items}},
        %{
          assigns: %{
            route_spec: %{route_id: :redeem},
            redemption_wallet: wallet,
            open_sea_lookup: name
          }
        } = socket
      ) do
    status = if items.animata == [] and items.regents_club == [], do: :empty, else: :ready

    {:noreply,
     assign(socket, open_sea_lookup: nil, owned_collectibles: Map.put(items, :status, status))}
  end

  def handle_async(
        {:open_sea, _wallet} = name,
        _result,
        %{assigns: %{open_sea_lookup: name}} = socket
      ),
      do:
        {:noreply,
         assign(socket,
           open_sea_lookup: nil,
           owned_collectibles: Map.put(socket.assigns.owned_collectibles, :status, :unavailable)
         )}

  def handle_async({:open_sea, _}, _result, socket), do: {:noreply, socket}

  def handle_async(
        {:wallet_transaction, scope, observation_id} = name,
        {:ok, result},
        socket
      )
      when scope in [:staking, :redemption] and
             result in [:success, :reverted, :delayed, :unavailable] do
    {:noreply,
     socket
     |> release_wallet_observation(name)
     |> push_transaction_result(scope, observation_id, result)}
  end

  def handle_async({:wallet_transaction, scope, observation_id} = name, _result, socket)
      when scope in [:staking, :redemption] do
    {:noreply,
     socket
     |> release_wallet_observation(name)
     |> push_transaction_result(scope, observation_id, :unavailable)}
  end

  @impl true
  def handle_event(
        "request_verified_connection",
        %{"action" => action, "provider" => provider},
        socket
      ) do
    with %Human{} <- human_actor(socket),
         {:ok, provider} <- linked_identity_provider(provider),
         {:ok, request} <- identity_request(action, provider, socket.assigns.verified_connections) do
      {:noreply,
       socket
       |> assign(
         verified_connections_notice: %{tone: :info, message: connection_started(request)}
       )
       |> push_event("verified-connections:request", request)}
    else
      _error ->
        {:noreply,
         assign(socket,
           verified_connections_notice: %{
             tone: :error,
             message: "That connection couldn’t be updated. Refresh the page and try again."
           }
         )}
    end
  end

  def handle_event(
        "load_more_names",
        _params,
        %{assigns: %{route_spec: %{route_id: :account}}} = socket
      ),
      do: {:noreply, load_more_names(socket)}

  def handle_event("load_more_names", _params, socket), do: {:noreply, socket}

  def handle_event(
        "check_claim_name",
        %{"name" => name},
        %{assigns: %{route_spec: %{route_id: :account}}} = socket
      )
      when is_binary(name),
      do: {:noreply, assign(socket, account_claim_name: check_claim_name(socket, name))}

  def handle_event("check_claim_name", _params, socket), do: {:noreply, socket}

  def handle_event(
        "claim_name",
        %{"name" => name},
        %{assigns: %{route_spec: %{route_id: :account}}} = socket
      )
      when is_binary(name),
      do: {:noreply, claim_name(socket, name)}

  def handle_event("claim_name", _params, socket), do: {:noreply, socket}

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

    {:noreply, assign(socket, verified_connections_notice: notice)}
  end

  def handle_event(event, params, socket)
      when event in [
             "redemption_active_wallet",
             "redemption_selection_changed",
             "prepare_redemption",
             "refresh_redemption",
             "select_owned_animata",
             "show_more_collectibles"
           ],
      do: handle_redemption_event(event, params, socket)

  def handle_event(
        "staking_active_wallet",
        params,
        %{assigns: %{route_spec: %{route_id: :stake}}} = socket
      ) do
    wallet = normalized_wallet(params["address"])

    if wallet == socket.assigns.staking_wallet,
      do: {:noreply, socket},
      else: {:noreply, adopt_staking_wallet(socket, wallet)}
  end

  def handle_event("staking_active_wallet", _params, socket), do: {:noreply, socket}

  # While the sign-in and the active wallet disagree, the Stake page sends its
  # action clicks here instead of to a wallet: the page carries no transaction
  # parameters, so nothing can be built, and the visitor is asked to come back
  # with the wallet their sign-in names.
  def handle_event(
        "refuse_staking_action",
        _params,
        %{assigns: %{route_spec: %{route_id: :stake}} = assigns} = socket
      ) do
    case transaction_gate(assigns.access_context, assigns.staking_wallet) do
      {:mismatch, request} -> {:noreply, assign(socket, wallet_reconnect: request)}
      _gate -> {:noreply, socket}
    end
  end

  def handle_event("refuse_staking_action", _params, socket), do: {:noreply, socket}

  def handle_event("dismiss_wallet_reconnect", _params, socket),
    do: {:noreply, assign(socket, wallet_reconnect: nil)}

  def handle_event(
        "select_staking_action",
        %{"mode" => mode},
        %{assigns: %{staking_action: mode}} = socket
      )
      when mode in ["stake", "unstake"],
      do: {:noreply, socket}

  def handle_event("select_staking_action", %{"mode" => mode}, socket)
      when mode in ["stake", "unstake"],
      do:
        {:noreply, assign(socket, staking_action: mode, staking_amount: "", staking_notice: nil)}

  def handle_event("select_staking_action", _params, socket), do: {:noreply, socket}

  def handle_event("fill_staking_amount", %{"portion" => portion}, socket)
      when portion in ["half", "max"] do
    case Staking.spendable(socket.assigns.staking, socket.assigns.staking_action) do
      :unavailable ->
        {:noreply, socket}

      amount ->
        {:noreply,
         assign(socket,
           staking_amount: token_amount(portioned(amount, portion)),
           staking_notice: nil
         )}
    end
  end

  def handle_event("fill_staking_amount", _params, socket), do: {:noreply, socket}

  def handle_event("staking_amount_changed", %{"amount" => amount}, socket),
    do: {:noreply, assign(socket, staking_amount: amount, staking_notice: nil)}

  def handle_event("refresh_staking", _params, socket),
    do: {:noreply, read_connected_wallet(socket)}

  def handle_event("refresh_shared_snapshot", _params, socket),
    do: {:noreply, read_shared_snapshot(socket)}

  # The Stake footer asks for both readings at once, on the same terms each is
  # asked for on its own.
  def handle_event("refresh_data", _params, socket),
    do: {:noreply, socket |> read_connected_wallet() |> read_shared_snapshot()}

  def handle_event(
        "observe_staking_transaction",
        params,
        %{assigns: %{route_spec: %{route_id: :stake}}} = socket
      ),
      do: {:noreply, start_transaction_observation(socket, :staking, params)}

  def handle_event("observe_staking_transaction", _params, socket), do: {:noreply, socket}

  def handle_event(
        "observe_redemption_transaction",
        params,
        %{assigns: %{route_spec: %{route_id: :redeem}}} = socket
      ),
      do: {:noreply, start_transaction_observation(socket, :redemption, params)}

  def handle_event("observe_redemption_transaction", _params, socket), do: {:noreply, socket}

  # One visitor's refresh re-reads the contract for everyone. Only the contract
  # figures are replaced: each page keeps whatever it knows about its own
  # connected wallet, still labelled with the block that wallet was read at, and
  # a wallet already answered for is never re-read on its own.
  @impl true
  def handle_info(
        {:staking_snapshot, protocol},
        %{assigns: %{route_spec: %{route_id: route_id}}} = socket
      )
      when route_id in [:stake, :app] do
    {:noreply,
     socket
     |> assign(
       staking: StakingFacts.adopt_protocol(socket.assigns.staking, protocol),
       staking_shared_reading: false,
       staking_status: :ready
     )
     |> read_unanswered_wallet()}
  end

  def handle_info({:staking_snapshot, _protocol}, socket), do: {:noreply, socket}

  # The session has already re-read the account by the time this arrives, so
  # what the chain answered is on the socket; only the Account page reports
  # whether the check found anything to record.
  def handle_info(
        {:ens_lookup_finished, _account_id},
        %{assigns: %{route_spec: %{route_id: :account}}} = socket
      ) do
    case current_account(socket.assigns.access_context) do
      %{ens_identity: %{}} -> {:noreply, assign(socket, account_ens: :ready)}
      _unanswered -> {:noreply, assign(socket, account_ens: :unavailable)}
    end
  end

  def handle_info({:ens_lookup_finished, _account_id}, socket), do: {:noreply, socket}

  # Only the pages that asked for the reading hear that it failed, and what they
  # were already showing stays on screen.
  def handle_info({:staking_snapshot_unavailable, _reason}, socket) do
    {:noreply,
     socket
     |> assign(staking_shared_reading: false)
     |> shared_read_failed()}
  end

  defp handle_redemption_event(
         _event,
         _params,
         %{assigns: %{route_spec: %{route_id: route_id}}} = socket
       )
       when route_id != :redeem,
       do: {:noreply, socket}

  defp handle_redemption_event("redemption_active_wallet", params, socket) do
    wallet = normalized_wallet(params["address"])

    if wallet == socket.assigns.redemption_wallet,
      do: {:noreply, socket},
      else: {:noreply, adopt_redemption_wallet(socket, wallet)}
  end

  defp handle_redemption_event("redemption_selection_changed", params, socket) do
    socket =
      assign(socket,
        redemption_collection: params["collection"] || socket.assigns.redemption_collection,
        redemption_token_id: params["token_id"] || "",
        redemption_notice: nil
      )

    {:noreply, read_selection(socket)}
  end

  defp handle_redemption_event(
         "select_owned_animata",
         %{"collection" => collection, "token-id" => token_id},
         socket
       ) do
    socket =
      assign(socket,
        redemption_collection: collection,
        redemption_token_id: token_id,
        redemption_notice: nil
      )

    {:noreply, read_selection(socket)}
  end

  defp handle_redemption_event(
         "prepare_redemption",
         %{"action" => action, "attempt_id" => attempt_id},
         socket
       )
       when is_binary(attempt_id) and attempt_id != "" do
    gate = transaction_gate(socket.assigns.access_context, socket.assigns.redemption_wallet)

    case redemption_attempt(gate, action, socket) do
      {:ok, envelope} ->
        {:noreply,
         socket
         |> assign(redemption_notice: nil)
         |> push_event("redemption:wallet-action", %{
           attempt_id: attempt_id,
           envelope: envelope
         })}

      {:refused, notice} ->
        {:noreply,
         socket
         |> assign(redemption_notice: notice, wallet_reconnect: reconnect_request(gate))
         |> push_event("redemption:wallet-refusal", %{
           attempt_id: attempt_id,
           sign_in: gate == :sign_in
         })}
    end
  end

  defp handle_redemption_event("prepare_redemption", _params, socket), do: {:noreply, socket}

  defp handle_redemption_event("refresh_redemption", params, socket) do
    socket =
      if params["refresh_owned"] in [true, "true"] and
           is_binary(socket.assigns.redemption_wallet) do
        # A confirmed redemption is the one moment the collection on screen is
        # known to be out of date. The cache honours one such reset per wallet
        # per cache window, so a page repeating the request buys no extra reads.
        HoldingsCache.invalidate(socket.assigns.redemption_wallet)

        socket
        |> cancel_open_sea_lookup()
        |> assign(
          owned_collectibles: Map.put(socket.assigns.owned_collectibles, :status, :refreshing)
        )
      else
        socket
      end

    {:noreply,
     start_redemption_read(socket,
       preserve_snapshot: true,
       announce_refresh: true,
       lookup_owned: true
     )}
  end

  defp handle_redemption_event("show_more_collectibles", _params, socket) do
    total =
      length(socket.assigns.owned_collectibles.animata) +
        length(socket.assigns.owned_collectibles.regents_club)

    {:noreply,
     assign(socket,
       owned_collectibles_limit: min(socket.assigns.owned_collectibles_limit + 24, total)
     )}
  end

  # Nothing is prepared for a visitor who has not signed in, and nothing for one
  # whose sign-in names a wallet the browser no longer has active.
  defp redemption_attempt(:ready, action, socket) do
    case prepare_redemption(action, socket) do
      {:ok, envelope} ->
        {:ok, envelope}

      {:error, _reason} ->
        {:refused, %{tone: :error, message: @redemption_preparation_failure_notice}}
    end
  end

  defp redemption_attempt(_gate, _action, _socket), do: {:refused, nil}

  @impl true
  def render(assigns) do
    ~H"""
    <.shell
      route_spec={@route_spec}
      account_control={@account_control}
      shell_instance={@shell_instance}
      theme={@theme}
    >
      <:content>
        <FormationLive.page :if={@route_spec.route_id == :formation} />

        <RegentProfileLive.page
          :if={@route_spec.route_id == :regent_profile}
          regent={@regent}
          status={@regent_status}
        />

        <RegentOpsLive.page
          :if={@route_spec.route_id == :app}
          reading={not is_nil(@staking_read)}
          staking={@staking}
          status={@staking_status}
          notice={@staking_notice}
          account_control={@account_control}
          account={current_account(@access_context)}
        />

        <AccountLive.page
          :if={@route_spec.route_id == :account}
          account={current_account(@access_context)}
          account_control={@account_control}
          ens={@account_ens}
          names={@account_names}
          names_stream={@streams.account_names}
          claims={@account_claims}
          claim_name={@account_claim_name}
          verified_connections={@verified_connections}
          verified_connections_notice={@verified_connections_notice}
        />

        <.page
          :if={@route_spec.route_id == :stake}
          staking={@staking}
          status={@staking_status}
          wallet={@staking_wallet}
          action={@staking_action}
          amount={@staking_amount}
          notice={@staking_notice}
          reading={staking_reading?(assigns)}
          shared_reading={@staking_shared_reading}
          signed_in={authenticated?(@access_context)}
          spendable={Staking.spendable(@staking, @staking_action)}
          amount_notice={staking_amount_notice(assigns)}
          available_claims={Staking.available_claims(@staking)}
          actions={gate_state(transaction_gate(@access_context, @staking_wallet))}
        />

        <.redemption_page
          :if={@route_spec.route_id == :redeem}
          redemption={@redemption}
          status={@redemption_status}
          wallet={@redemption_wallet}
          collection={@redemption_collection}
          token_id={@redemption_token_id}
          notice={@redemption_notice}
          reading={redemption_reading?(assigns)}
          signed_in={authenticated?(@access_context)}
          refresh_block={@redemption_refresh_block}
          step={redemption_step(assigns)}
          owned_collectibles={@owned_collectibles}
          owned_collectibles_limit={@owned_collectibles_limit}
          actions={gate_state(transaction_gate(@access_context, @redemption_wallet))}
        />

        <RedeemGalleryLive.page :if={@route_spec.route_id == :redeem_gallery} />

        <ProductLive.page
          :if={@route_spec.route_id in [:autolaunch, :techtree, :patchbay]}
          product={@route_spec.route_id}
        />

        <.wallet_reconnect_dialog :if={@wallet_reconnect} request={@wallet_reconnect} />
      </:content>
    </.shell>
    """
  end

  # An anonymous visitor to either page buys no chain read at all: the shared
  # contract reading is already on the server and is painted as it is. Only a
  # signed-in account has a wallet to look up here, and that lookup takes its
  # own fresh block.
  defp maybe_start_staking(socket, %{route_id: :app}, generation) do
    socket = socket |> clear_staking_form() |> paint_shared_snapshot()

    case staking_actor(socket) do
      %Human{} = actor ->
        start_wallet_read(socket, generation, fn -> Staking.account(actor: actor) end)

      nil ->
        socket
    end
  end

  defp maybe_start_staking(socket, %{route_id: :stake}, generation),
    do: socket |> paint_shared_snapshot() |> start_staking_read(generation)

  defp maybe_start_staking(socket, _route, _generation),
    do: socket |> clear_staking_form() |> assign(staking: nil, staking_status: :loading)

  # With no successful shared reading yet, there is nothing honest to show and
  # nothing this visitor can do about it alone; the page says so and a signed-in
  # visitor is offered the control that takes one.
  # The disconnected HTTP render can use the server cache immediately. Never
  # start a chain or per-wallet request here; those remain asynchronous after
  # connection, and no private wallet facts enter this shared projection.
  defp paint_initial_staking(socket, %{route_id: route_id}) when route_id in [:app, :stake],
    do: paint_shared_snapshot(socket, :loading)

  defp paint_initial_staking(socket, _route), do: socket

  defp paint_shared_snapshot(socket, empty_status \\ :error) do
    case SnapshotCache.snapshot() do
      nil ->
        assign(socket, staking: nil, staking_status: empty_status)

      protocol ->
        assign(socket,
          staking: StakingFacts.merge(protocol, StakingFacts.blank_wallet()),
          staking_status: :ready
        )
    end
  end

  defp clear_staking_form(socket),
    do:
      assign(socket,
        staking_action: "stake",
        staking_amount: "",
        staking_wallet: nil,
        staking_notice: nil
      )

  # A wallet reading that failed leaves every figure it would have carried
  # marked unavailable, beside the contract reading it never spoke about. With
  # no contract reading to sit beside there is nothing to mark.
  defp wallet_read_failed(%{assigns: %{staking: nil}} = socket), do: shared_read_failed(socket)

  defp wallet_read_failed(socket) do
    assign(socket,
      staking:
        StakingFacts.merge(
          socket.assigns.staking,
          StakingFacts.unavailable_wallet(socket.assigns.staking_wallet)
        ),
      staking_status: :ready,
      staking_notice: %{tone: :error, message: @staking_refresh_failure_notice}
    )
  end

  # Only the contract reading can leave a page with nothing honest to show. A
  # reading that fails leaves the previous one exactly where it was.
  defp shared_read_failed(socket) do
    if socket.assigns.staking do
      assign(socket,
        staking_status: :ready,
        staking_notice: %{
          tone: :error,
          message: @staking_refresh_failure_notice
        }
      )
    else
      assign(socket, staking: nil, staking_status: :error)
    end
  end

  defp clear_staking_refresh_failure(%{message: @staking_refresh_failure_notice}), do: nil
  defp clear_staking_refresh_failure(notice), do: notice

  # This socket's own connected wallet, read again at a fresh block. Any
  # connected wallet may do this, signed in or not.
  defp read_connected_wallet(socket),
    do: start_staking_read(socket, socket.assigns.content_generation)

  # Re-reading the contract replaces what every visitor sees, so only a
  # signed-in session may ask for it, and the socket's own session decides that
  # here rather than the markup that offered the control.
  defp read_shared_snapshot(socket) do
    if authenticated?(socket.assigns.access_context) do
      request_shared_refresh(socket)
    else
      socket
    end
  end

  defp request_shared_refresh(socket) do
    case SnapshotCache.refresh() do
      :ok ->
        assign(socket, staking_shared_reading: true, staking_notice: nil)

      {:error, :refresh_too_soon} ->
        assign(socket,
          staking_notice: %{tone: :info, message: @shared_refresh_budget_notice}
        )
    end
  end

  # A wallet connected while there was no contract reading has nothing to be
  # shown beside, so nothing was bought for it. The moment a contract reading
  # arrives that wallet is looked up, rather than leaving somebody to ask for a
  # reading they already asked for. A wallet the page has an answer for, however
  # that answer turned out, is left alone.
  defp read_unanswered_wallet(%{assigns: %{staking_wallet: nil}} = socket), do: socket

  defp read_unanswered_wallet(
         %{assigns: %{staking: %{wallet_address: wallet}, staking_wallet: wallet}} = socket
       ),
       do: socket

  defp read_unanswered_wallet(socket),
    do: start_staking_read(socket, socket.assigns.content_generation)

  # With no wallet connected there is nothing about this visitor to read, and
  # the shared contract reading on screen already answers for everyone.
  defp start_staking_read(%{assigns: %{staking_wallet: nil}} = socket, _generation), do: socket

  defp start_staking_read(socket, generation) do
    wallet = socket.assigns.staking_wallet
    start_wallet_read(socket, generation, fn -> Staking.account_for_wallet(wallet) end)
  end

  # A wallet reading answers for one account and carries no contract figures, so
  # with no shared reading on screen there is nothing for it to be shown beside.
  # Buying one anyway spends four round trips on an answer that would be thrown
  # away, so it is not bought until the contract reading is there.
  defp start_wallet_read(%{assigns: %{staking: nil}} = socket, _generation, _read), do: socket

  defp start_wallet_read(socket, generation, read) do
    name = {:staking, generation}

    socket
    |> cancel_async(name)
    |> assign(staking_read: %{name: name})
    |> start_async(name, fn -> {generation, read.()} end)
  end

  defp release_staking_read(%{assigns: %{staking_read: %{name: name}}} = socket, name),
    do: assign(socket, staking_read: nil)

  defp release_staking_read(socket, _), do: socket
  defp staking_reading?(%{staking_read: nil}), do: false
  defp staking_reading?(_), do: true

  defp current_account(%{principal: {:human, account}}), do: account
  defp current_account(_access_context), do: nil

  # Sending a transaction is something a signed-in visitor does with the wallet
  # their sign-in names. Reading these pages and connecting a wallet to see a
  # position stay open to everyone; only these three answers stand between a
  # click and a wallet request.
  defp transaction_gate(access_context, active_wallet) do
    case current_account(access_context) do
      nil -> :sign_in
      account -> wallet_gate(account_wallet(account), active_wallet)
    end
  end

  # A sign-in stays fixed to the account it was made with, while these pages
  # follow whichever wallet the browser has active. Two different addresses mean
  # nothing signed here would come from the account the header names, so an
  # action click asks for that wallet back instead of reaching the other one.
  defp wallet_gate(account_wallet, active_wallet)
       when is_binary(account_wallet) and is_binary(active_wallet) and
              account_wallet != active_wallet,
       do:
         {:mismatch,
          "Please reconnect to the active wallet '#{RegentFormat.short_wallet(account_wallet)}' to interact onchain."}

  defp wallet_gate(_account_wallet, _active_wallet), do: :ready

  defp gate_state({:mismatch, _request}), do: :mismatch
  defp gate_state(gate), do: gate

  defp reconnect_request({:mismatch, request}), do: request
  defp reconnect_request(_gate), do: nil

  defp account_wallet(account), do: normalized_wallet(Map.get(account, :wallet_address))

  # Sign-in read the wallet's primary name once. A wallet never answered for, or
  # last answered for more than a day ago, is asked again when its own page
  # opens, and the page takes the answer as it lands. Only the connected page
  # asks, so the static render does not start a lookup the connected mount
  # would start again a moment later.
  defp load_account_ens(socket, %{route_id: :account}) do
    case current_account(socket.assigns.access_context) do
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

  defp load_account_ens(socket, _route_spec), do: assign(socket, account_ens: nil)

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

  defp load_verified_connections(socket, %{route_id: :account}) do
    reload_verified_connections(socket)
  end

  defp load_verified_connections(socket, _route_spec) do
    assign(socket, verified_connections: [], verified_connections_notice: nil)
  end

  defp reload_verified_connections(socket) do
    case human_actor(socket) do
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

  defp load_regent_route(socket, %{route_id: :regent_profile}, %{"slug" => slug}) do
    case Formation.get_public_regent_profile(slug) do
      {:ok, nil} -> assign(socket, regent: nil, regent_status: :empty)
      {:ok, regent} -> assign(socket, regent: regent, regent_status: :ready)
      {:error, _error} -> assign(socket, regent: nil, regent_status: :error)
    end
  end

  defp load_regent_route(socket, _route_spec, _params) do
    regent = socket.assigns.current_regent
    assign(socket, regent: regent, regent_status: if(regent, do: :ready, else: :empty))
  end

  # The account page lists the names the signed-in wallets hold. That read is
  # the account's own, made with the wallets its sign-in verified, so nothing
  # the browser sends can widen it.
  defp load_account_names(socket, %{route_id: :account}) do
    case human_actor(socket) do
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

  defp load_account_names(socket, _route_spec), do: assign(socket, account_names: nil)

  # The list is oldest first and grows a page at a time as the reader reaches
  # its end. The rows go to the browser and only the place to continue from is
  # kept here; a page that cannot be read leaves the rows already shown in place.
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
           actor: human_actor(socket),
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
  defp load_account_claims(socket, %{route_id: :account}) do
    claims =
      case human_actor(socket) do
        %Human{wallet_addresses: []} -> %{free: 0, paid: 0}
        %Human{} = actor -> claims_available(actor)
        nil -> nil
      end

    assign(socket, account_claims: claims, account_claim_name: @blank_claim_name)
  end

  defp load_account_claims(socket, _route_spec),
    do: assign(socket, account_claims: nil, account_claim_name: @blank_claim_name)

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
    with %Human{} = actor <- human_actor(socket),
         {:ok, claim} <- Names.claim_free_name(name, actor: actor) do
      socket
      |> load_account_names(socket.assigns.route_spec)
      |> load_account_claims(socket.assigns.route_spec)
      |> assign(
        account_claim_name: %{@blank_claim_name | availability: {:claimed_now, claim.ens_fqdn}}
      )
    else
      nil ->
        socket

      {:error, _error} ->
        socket
        |> load_account_claims(socket.assigns.route_spec)
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
    case Names.label_claimed?(name, actor: human_actor(socket)) do
      {:ok, true} -> :claimed
      {:ok, false} -> :available
      {:error, _error} -> :unavailable
    end
  end

  defp human_actor(%{assigns: %{access_context: %{principal: {:human, account}}}}),
    do: %Human{human_account_id: account.id, wallet_addresses: account_wallets(account)}

  defp human_actor(_socket), do: nil

  defp account_wallets(account) do
    [account.wallet_address | List.wrap(account.wallet_addresses)]
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.downcase/1)
    |> Enum.uniq()
  end

  defp maybe_start_redemption(socket, %{route_id: :redeem}, _),
    do: start_redemption_read(socket, lookup_owned: true)

  defp maybe_start_redemption(socket, _, _) do
    socket
    |> cancel_redemption_read()
    |> cancel_open_sea_lookup()
    |> assign(
      redemption: nil,
      redemption_status: :loading,
      redemption_refresh_block: nil,
      redemption_notice: nil,
      redemption_snapshot_selection: nil,
      redemption_wallet: nil,
      owned_collectibles: %{status: :idle, animata: [], regents_club: []},
      owned_collectibles_limit: 24
    )
  end

  defp start_redemption_read(socket, options) do
    socket = cancel_redemption_read(socket)
    generation = socket.assigns.redemption_generation + 1
    name = {:redemption, generation}
    wallet = socket.assigns.redemption_wallet
    collection = socket.assigns.redemption_collection
    token_id = parsed_token_id(socket.assigns.redemption_token_id)

    preserve_snapshot =
      Keyword.get(options, :preserve_snapshot, false) && not is_nil(socket.assigns.redemption)

    announce_refresh = Keyword.get(options, :announce_refresh, false)

    socket
    |> assign(
      redemption: if(preserve_snapshot, do: socket.assigns.redemption),
      redemption_status: if(preserve_snapshot, do: :ready, else: :loading),
      redemption_refresh_block:
        if(announce_refresh, do: nil, else: socket.assigns.redemption_refresh_block),
      redemption_notice: if(announce_refresh, do: nil, else: socket.assigns.redemption_notice),
      redemption_generation: generation,
      redemption_read: %{
        name: name,
        selection: {collection, token_id},
        announce_refresh: announce_refresh,
        lookup_owned: Keyword.get(options, :lookup_owned, false)
      }
    )
    |> start_async(name, fn ->
      {generation,
       if(wallet,
         do: Redemption.account_for_wallet(wallet, collection, token_id),
         else: Redemption.overview()
       )}
    end)
  end

  # A keystroke that leaves the selection Base was asked about unchanged buys
  # no read: the reading in flight or the snapshot on screen already answers
  # it. Only a selection neither of them covers is read.
  defp read_selection(socket) do
    selection = current_redemption_selection(socket.assigns)

    cond do
      match?(%{selection: ^selection}, socket.assigns.redemption_read) -> socket
      redemption_selection_ready?(socket.assigns) -> cancel_redemption_read(socket)
      true -> start_redemption_read(socket, preserve_snapshot: true)
    end
  end

  defp adopt_redemption_wallet(socket, wallet),
    do:
      socket
      |> cancel_open_sea_lookup()
      |> assign(
        redemption_wallet: wallet,
        redemption: public_redemption_snapshot(socket.assigns.redemption),
        redemption_status: if(socket.assigns.redemption, do: :ready, else: :loading),
        redemption_refresh_block: nil,
        redemption_notice: nil,
        wallet_reconnect: nil,
        redemption_snapshot_selection: nil,
        owned_collectibles: %{status: :idle, animata: [], regents_club: []},
        owned_collectibles_limit: 24
      )
      |> start_redemption_read(preserve_snapshot: true, lookup_owned: true)

  defp redemption_read_failed(socket, _) do
    collectibles =
      case socket.assigns.owned_collectibles do
        %{status: :refreshing} = current -> Map.put(current, :status, :unavailable)
        current -> current
      end

    if socket.assigns.redemption do
      assign(socket,
        redemption_status: :ready,
        owned_collectibles: collectibles,
        redemption_notice: %{
          tone: :error,
          message: "Refresh failed. The last confirmed Base snapshot remains on screen."
        }
      )
    else
      assign(socket,
        redemption: nil,
        redemption_status: :error,
        owned_collectibles: collectibles,
        redemption_snapshot_selection: nil
      )
    end
  end

  # Every observation polls Base for up to one minute, so a socket may only ever
  # hold @max_wallet_observations of them at once. A repeated or overflowing push
  # buys no chain reads, but it is still answered: the transaction was sent, so
  # the page is told the confirmation is unavailable rather than left waiting on
  # a result that would never arrive. The wallet send path is never refused.
  defp start_transaction_observation(socket, scope, params) do
    observation_id = params["observation_id"]

    if is_binary(observation_id) and byte_size(observation_id) in 1..128 do
      name = {:wallet_transaction, scope, observation_id}
      observations = socket.assigns.wallet_observations

      if MapSet.member?(observations, name) or
           MapSet.size(observations) >= @max_wallet_observations do
        push_transaction_result(socket, scope, observation_id, :unavailable)
      else
        transaction = Map.take(params, ["hash", "signer", "to", "data"])

        socket
        |> assign(wallet_observations: MapSet.put(observations, name))
        |> start_async(name, fn -> TransactionObserver.observe(transaction, scope) end)
      end
    else
      socket
    end
  end

  defp release_wallet_observation(socket, name),
    do:
      assign(socket, wallet_observations: MapSet.delete(socket.assigns.wallet_observations, name))

  defp push_transaction_result(socket, scope, observation_id, result) do
    event =
      if scope == :staking,
        do: "staking:transaction-result",
        else: "redemption:transaction-result"

    push_event(socket, event, %{observation_id: observation_id, result: result})
  end

  defp cancel_redemption_read(%{assigns: %{redemption_read: nil}} = socket), do: socket

  defp cancel_redemption_read(socket),
    do:
      socket |> cancel_async(socket.assigns.redemption_read.name) |> assign(redemption_read: nil)

  defp release_redemption_read(%{assigns: %{redemption_read: %{name: name}}} = socket, name),
    do: assign(socket, redemption_read: nil)

  defp release_redemption_read(socket, _), do: socket
  defp redemption_reading?(%{redemption_read: nil}), do: false
  defp redemption_reading?(_), do: true

  defp redemption_selection_ready?(assigns) do
    not is_nil(Map.get(assigns, :redemption)) and
      Map.get(assigns, :redemption_snapshot_selection) == current_redemption_selection(assigns)
  end

  defp current_redemption_selection(assigns),
    do:
      {Map.get(assigns, :redemption_collection),
       parsed_token_id(Map.get(assigns, :redemption_token_id))}

  defp redemption_step(assigns) do
    if redemption_selection_ready?(assigns),
      do: Redemption.next_step(assigns.redemption, assigns.redemption_wallet),
      else: nil
  end

  # Editing a token ID re-reads Base, but it says nothing new about which
  # collectibles the wallet holds. Only a wallet change or an explicit refresh
  # asks for the collection again, so typing never spends the page's share of
  # lookups and an outage cannot cost a visitor the panel for the rest of a
  # minute.
  defp maybe_start_open_sea_lookup(socket, true, generation),
    do: start_open_sea_lookup(socket, generation)

  defp maybe_start_open_sea_lookup(socket, false, _generation), do: socket

  # Every owned-collectible lookup spends the server's own OpenSea credentials on
  # behalf of a visitor who needs no account, so one connection may only start
  # @default_open_sea_lookups_per_minute of them a minute. A page past its share
  # is told the lookup is unavailable, which is the same thing it is told when
  # OpenSea itself cannot answer: the manual collection and token ID fields stay
  # open and no wallet action is refused.
  defp start_open_sea_lookup(
         %{
           assigns: %{
             redemption_wallet: wallet,
             route_spec: %{route_id: :redeem},
             owned_collectibles: %{status: status}
           }
         } = socket,
         _generation
       )
       when is_binary(wallet) and status in [:idle, :unavailable, :refreshing] do
    now = System.monotonic_time(:millisecond)

    recent =
      Enum.filter(socket.assigns.open_sea_lookup_starts, &(&1 > now - @open_sea_lookup_window))

    if length(recent) >= open_sea_lookups_per_minute() do
      assign(socket,
        open_sea_lookup_starts: recent,
        owned_collectibles: Map.put(socket.assigns.owned_collectibles, :status, :unavailable)
      )
    else
      name = {:open_sea, wallet}

      socket
      |> assign(
        open_sea_lookup: name,
        open_sea_lookup_starts: [now | recent],
        owned_collectibles: loading_collectibles(socket.assigns.owned_collectibles)
      )
      |> start_async(name, fn -> OpenSea.fetch_owned_collectibles(wallet) end)
    end
  end

  defp start_open_sea_lookup(socket, _), do: socket

  defp open_sea_lookups_per_minute,
    do:
      Application.get_env(
        :ash_platform,
        :opensea_lookups_per_minute,
        @default_open_sea_lookups_per_minute
      )

  defp loading_collectibles(%{status: :idle}),
    do: %{status: :loading, animata: [], regents_club: []}

  defp loading_collectibles(collectibles), do: collectibles
  defp cancel_open_sea_lookup(%{assigns: %{open_sea_lookup: nil}} = socket), do: socket

  defp cancel_open_sea_lookup(socket),
    do: socket |> cancel_async(socket.assigns.open_sea_lookup) |> assign(open_sea_lookup: nil)

  defp prepare_redemption(action, socket) do
    wallet = socket.assigns.redemption_wallet
    collection = socket.assigns.redemption_collection
    token_id = parsed_token_id(socket.assigns.redemption_token_id)

    case action do
      "approve_nft_collection" when is_integer(token_id) ->
        Redemption.prepare_nft_approval(wallet, collection, token_id)

      "approve_exact_usdc" when is_integer(token_id) ->
        Redemption.prepare_usdc_approval(wallet, collection, token_id)

      "redeem" when is_integer(token_id) ->
        Redemption.prepare_redeem(wallet, collection, token_id)

      "claim" ->
        Redemption.prepare_claim(wallet)

      _ ->
        {:error, :invalid_token_selection}
    end
  end

  defp parsed_token_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {token_id, ""} when token_id in 1..999 -> token_id
      _ -> nil
    end
  end

  defp parsed_token_id(_value), do: nil

  # Ash wraps a generic action's error in an error class, so the typed refusal
  # the operation boundary returned is read back out of it and the copy can name
  # what actually happened.
  defp refusal(%Ash.Error.Invalid{errors: [%Ash.Error.Invalid.Unavailable{reason: reason} | _]}),
    do: reason

  defp refusal(reason), do: reason

  defp staking_preparation_error(:chain_unavailable),
    do: "Base could not be reached to check this wallet. Nothing was prepared. Try again shortly."

  defp staking_preparation_error(:staking_paused), do: "Staking is paused on Base right now."

  defp staking_preparation_error(:amount_above_balance),
    do: "That is more REGENT than this wallet holds."

  defp staking_preparation_error(:amount_above_capacity),
    do: "That is more REGENT than the staking contract can still take."

  defp staking_preparation_error(:amount_above_stake),
    do: "That is more REGENT than this wallet has staked."

  defp staking_preparation_error(_reason),
    do: "That action could not be prepared. Check the amount and wallet."

  defp staking_actor(%{assigns: %{access_context: %{principal: {:human, account}}}}),
    do: %Human{human_account_id: account.id}

  defp staking_actor(_socket), do: nil

  defp authenticated?(%{principal: {:human, _}}), do: true
  defp authenticated?(_), do: false

  # A different wallet's position is not this one's. The contract reading stays
  # exactly as it is while the new wallet is looked up at its own fresh block.
  defp adopt_staking_wallet(socket, wallet),
    do:
      socket
      |> assign(
        staking: forget_wallet_facts(socket.assigns.staking),
        staking_wallet: wallet,
        staking_amount: "",
        staking_notice: nil,
        wallet_reconnect: nil
      )
      |> start_staking_read(socket.assigns.content_generation)

  defp forget_wallet_facts(nil), do: nil

  defp forget_wallet_facts(staking),
    do: StakingFacts.merge(staking, StakingFacts.blank_wallet())

  defp public_redemption_snapshot(nil), do: nil

  defp public_redemption_snapshot(redemption) do
    Map.merge(redemption, %{
      wallet_address: nil,
      selected_collection: nil,
      token_id: nil,
      nft_owner: nil,
      nft_redeemed: false,
      nft_owner_unavailable: false,
      nft_approved: nil,
      usdc_balance_raw: nil,
      usdc_balance: nil,
      usdc_allowance_raw: nil,
      usdc_allowance: nil,
      claimable_raw: nil,
      claimable: nil,
      vest_pool_raw: nil,
      vest_pool: nil,
      vest_released_raw: nil,
      vest_released: nil,
      vest_claimed_raw: nil,
      vest_claimed: nil,
      vest_start: nil
    })
  end

  defp normalized_wallet(address) do
    case Address.normalize(address) do
      {:ok, wallet} -> wallet
      :error -> nil
    end
  end

  defp staking_amount_notice(%{staking: nil}), do: nil

  defp staking_amount_notice(%{staking: staking, staking_action: action, staking_amount: amount}) do
    case amount |> String.trim() |> Staking.parse_amount() do
      {:ok, requested} -> staking |> Staking.limit_refusal(action, requested) |> limit_copy()
      {:error, _} -> blank_or_invalid(amount)
    end
  end

  defp blank_or_invalid(amount),
    do: if(String.trim(amount) == "", do: nil, else: "Enter an amount in REGENT above zero.")

  defp limit_copy(nil), do: nil

  # Nothing here refuses the amount: the figure it would be checked against is
  # missing, and the wallet still decides.
  defp limit_copy(:chain_unavailable),
    do: "Your position is unavailable right now, so this amount is not checked against it."

  defp limit_copy(reason), do: staking_preparation_error(reason)
  defp portioned(balance, "half"), do: div(balance, 2)
  defp portioned(balance, "max"), do: balance
end
