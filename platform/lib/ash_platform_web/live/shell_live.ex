defmodule AshPlatformWeb.ShellLive do
  use AshPlatformWeb, :live_view

  import AshPlatformWeb.Components.Shell
  import AshPlatformWeb.ShellLive.Identity
  import AshPlatformWeb.StakeLive

  alias AshPlatform.{Formation, OpenSea, Redemption, Staking}
  alias AshPlatform.Actors.Human
  alias AshPlatform.OpenSea.HoldingsCache
  alias AshPlatform.Redemption.Steps, as: RedemptionSteps
  alias AshPlatform.Staking.Facts, as: StakingFacts
  alias AshPlatform.Staking.SnapshotCache
  alias AshPlatformWeb.AccountLive
  alias AshPlatformWeb.AutolaunchLive
  alias AshPlatformWeb.EventInput
  alias AshPlatformWeb.ProductLive
  alias AshPlatformWeb.PublicDocuments
  alias AshPlatformWeb.RedeemGalleryLive
  alias AshPlatformWeb.RedeemLive
  alias AshPlatformWeb.RegentOpsLive
  alias AshPlatformWeb.RegentProfileLive
  alias AshPlatformWeb.RouteCatalog
  alias AshPlatformWeb.ShellLive.{Account, Gallery, OpenSeaBudget}

  @refresh_failure_notice "Couldn’t update just now. The figures shown are from the last successful reading."
  # Names the budget it belongs to. The Redeem page has its own, unrelated
  # per-visitor limit on looking up owned NFTs, and the two refusals must never
  # read as the same thing.
  @shared_refresh_budget_notice "Contract data was refreshed for everyone moments ago. Ask for a new reading again in a few seconds."
  @redemption_collections ~w(animata_i animata_ii)
  @account_events Account.events()
  # Longer than any collection or token ID; the token ID input stops there too.
  @redemption_selection_limits %{"collection" => 16, "token_id" => 16}

  @impl true
  def mount(params, session, socket) do
    route_spec = RouteCatalog.fetch!(socket.assigns.live_action, params)
    socket = assign(socket, :theme, session["theme"])

    if connected?(socket) do
      Phoenix.PubSub.subscribe(AshPlatform.PubSub, SnapshotCache.topic())
    end

    {:ok,
     socket
     |> Account.init()
     |> Gallery.init()
     |> OpenSeaBudget.init()
     |> assign(
       content_generation: 0,
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
       staking: nil,
       staking_wallet: nil,
       staking_notice: nil,
       staking_read: nil,
       staking_shared_reading: false,
       staking_status: :loading,
       browser_wallet: nil,
       route_spec: route_spec,
       shell_instance: System.unique_integer([:positive, :monotonic])
     )}
  end

  @impl true
  def handle_params(params, uri, socket) do
    route_spec = RouteCatalog.fetch!(socket.assigns.live_action, params)
    generation = socket.assigns.content_generation + 1

    socket =
      socket
      |> assign(content_generation: generation, route_spec: route_spec, route_params: params)
      |> load_regent_route(route_spec, params)
      |> assign_page(route_spec, uri)
      |> Account.route(route_spec)
      |> assign_position_wallet(route_spec)

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
  def handle_async({:agent_activity, _id} = name, result, socket),
    do: {:noreply, Account.settle_activity(socket, name, result)}

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

  def handle_async({:gallery_owned, _account_id} = name, result, socket),
    do: {:noreply, Gallery.settle(socket, name, result)}

  @impl true
  def handle_event("toggle_my_passes", _params, socket),
    do: {:noreply, Gallery.toggle(socket)}

  def handle_event(event, params, socket) when event in @account_events,
    do: {:noreply, Account.handle_event(event, params, socket)}

  def handle_event(event, params, socket)
      when event in [
             "redemption_selection_changed",
             "refresh_redemption",
             "select_owned_animata",
             "show_more_collectibles"
           ],
      do: handle_redemption_event(event, params, socket)

  def handle_event("refresh_shared_snapshot", _params, socket),
    do: {:noreply, read_shared_snapshot(socket)}

  # The Stake footer asks for both readings at once, on the same terms each is
  # asked for on its own.
  def handle_event("refresh_data", _params, socket),
    do: {:noreply, socket |> read_connected_wallet() |> read_shared_snapshot()}

  # Anything else the page sent is not in a shape this page takes.
  def handle_event(_event, _params, socket),
    do: {:noreply, put_flash(socket, :error, EventInput.unreadable())}

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

  # The Stake actions heard which wallet Privy has active. Signed in, the figures
  # follow it when it is the account's own; any other wallet leaves them on the
  # account's first wallet while the actions ask the person to switch.
  def handle_info(
        {:stake_active_wallet, active},
        %{assigns: %{route_spec: %{route_id: :stake}}} = socket
      ) do
    socket = assign(socket, browser_wallet: active)
    wallet = position_wallet(socket.assigns)

    if wallet == socket.assigns.staking_wallet,
      do: {:noreply, socket},
      else: {:noreply, adopt_staking_wallet(socket, wallet)}
  end

  def handle_info({:stake_active_wallet, _active}, socket), do: {:noreply, socket}

  # A Stake step landed: this wallet's figures moved, so they are read again.
  def handle_info(:stake_step_landed, socket), do: {:noreply, read_connected_wallet(socket)}

  # The Redeem buttons heard which wallet Privy has active; the figures follow
  # it on the same terms as Stake's.
  def handle_info(
        {:redeem_active_wallet, active},
        %{assigns: %{route_spec: %{route_id: :redeem}}} = socket
      ) do
    socket = assign(socket, browser_wallet: active)
    wallet = position_wallet(socket.assigns)

    if wallet == socket.assigns.redemption_wallet,
      do: {:noreply, socket},
      else: {:noreply, adopt_redemption_wallet(socket, wallet)}
  end

  def handle_info({:redeem_active_wallet, _active}, socket), do: {:noreply, socket}

  # A Redeem step landed: the figures are read again, and after a redemption
  # the collection too.
  def handle_info(
        {:redeem_step_landed, name},
        %{assigns: %{route_spec: %{route_id: :redeem}}} = socket
      ),
      do: {:noreply, refresh_redemption(socket, name == "redeem")}

  def handle_info({:redeem_step_landed, _name}, socket), do: {:noreply, socket}

  def handle_info({:ens_lookup_finished, _account_id}, socket),
    do: {:noreply, Account.ens_finished(socket)}

  def handle_info(:agents_changed, socket), do: {:noreply, Account.agents_changed(socket)}

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

  defp handle_redemption_event("redemption_selection_changed", params, socket) do
    case EventInput.texts(params, @redemption_selection_limits) do
      {:ok, fields} ->
        select_redemption(
          socket,
          Map.get(fields, "collection", socket.assigns.redemption_collection),
          Map.get(fields, "token_id", "")
        )

      :error ->
        {:noreply, redemption_unreadable(socket)}
    end
  end

  defp handle_redemption_event("select_owned_animata", params, socket) do
    case EventInput.texts(params, %{"collection" => 16, "token-id" => 16}) do
      {:ok, %{"collection" => collection, "token-id" => token_id}} ->
        select_redemption(socket, collection, token_id)

      _unreadable ->
        {:noreply, redemption_unreadable(socket)}
    end
  end

  defp handle_redemption_event("refresh_redemption", _params, socket),
    do: {:noreply, refresh_redemption(socket, false)}

  defp handle_redemption_event("show_more_collectibles", _params, socket) do
    total =
      length(socket.assigns.owned_collectibles.animata) +
        length(socket.assigns.owned_collectibles.regents_club)

    {:noreply,
     assign(socket,
       owned_collectibles_limit: min(socket.assigns.owned_collectibles_limit + 24, total)
     )}
  end

  # Only the two collections are ever chosen; the token ID is read as typed.
  defp select_redemption(socket, collection, token_id)
       when collection in @redemption_collections do
    socket =
      assign(socket,
        redemption_collection: collection,
        redemption_token_id: token_id,
        redemption_notice: nil
      )

    {:noreply, read_selection(socket)}
  end

  defp select_redemption(socket, _collection, _token_id),
    do: {:noreply, redemption_unreadable(socket)}

  defp redemption_unreadable(socket),
    do: assign(socket, redemption_notice: %{tone: :error, message: EventInput.unreadable()})

  # A landed redemption is the one moment the collection on screen is known to
  # be out of date. The cache honours one such reset per wallet per cache
  # window, so repeated landings buy no extra reads.
  defp refresh_redemption(socket, refresh_owned) do
    socket =
      if refresh_owned and is_binary(socket.assigns.redemption_wallet) do
        HoldingsCache.invalidate(socket.assigns.redemption_wallet)

        socket
        |> cancel_open_sea_lookup()
        |> assign(
          owned_collectibles: Map.put(socket.assigns.owned_collectibles, :status, :refreshing)
        )
      else
        socket
      end

    start_redemption_read(socket,
      preserve_snapshot: true,
      announce_refresh: true,
      lookup_owned: true
    )
  end

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
          agents={@paired_agents}
          agent_pairing={@agent_pairing}
          agent_detail={@agent_detail}
          agent_notice={@agent_notice}
          agents_now={@agents_now}
        />

        <.page
          :if={@route_spec.route_id == :stake}
          staking={@staking}
          status={@staking_status}
          wallet={@staking_wallet}
          linked={linked_wallets(@access_context)}
          notice={@staking_notice}
          reading={staking_reading?(assigns)}
          shared_reading={@staking_shared_reading}
        />

        <.live_component
          :if={@route_spec.route_id == :redeem}
          module={RedeemLive}
          id="animata-redemption"
          redemption={@redemption}
          status={@redemption_status}
          wallet={@redemption_wallet}
          linked={linked_wallets(@access_context)}
          collection={@redemption_collection}
          token_id={@redemption_token_id}
          notice={@redemption_notice}
          reading={redemption_reading?(assigns)}
          refresh_block={@redemption_refresh_block}
          step={redemption_step(assigns)}
          owned_collectibles={@owned_collectibles}
          owned_collectibles_limit={@owned_collectibles_limit}
        />

        <RedeemGalleryLive.page
          :if={@route_spec.route_id == :redeem_gallery}
          signed_in={authenticated?(@access_context)}
          mine={@gallery_mine}
          owned={@gallery_owned}
        />

        <AutolaunchLive.page :if={@route_spec.route_id == :autolaunch} />

        <ProductLive.page
          :if={@route_spec.route_id in [:techtree, :patchbay]}
          product={@route_spec.route_id}
        />
      </:content>
    </.shell>
    """
  end

  # An anonymous visitor to either page buys no chain read at all: the shared
  # contract reading is already on the server and is painted as it is. Only a
  # signed-in account has a wallet to look up here, and that lookup takes its
  # own fresh block.
  defp maybe_start_staking(socket, %{route_id: :app}, generation) do
    socket = socket |> clear_staking_wallet() |> paint_shared_snapshot()

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
    do: socket |> clear_staking_wallet() |> assign(staking: nil, staking_status: :loading)

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

  defp clear_staking_wallet(socket), do: assign(socket, staking_wallet: nil, staking_notice: nil)

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
      staking_notice: %{tone: :error, message: @refresh_failure_notice}
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
          message: @refresh_failure_notice
        }
      )
    else
      assign(socket, staking: nil, staking_status: :error)
    end
  end

  defp clear_staking_refresh_failure(%{message: @refresh_failure_notice}), do: nil
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
  # The Overview reads the signed-in account's own wallet, so one never read
  # because the contract reading was missing is read once that reading arrives.
  defp read_unanswered_wallet(
         %{
           assigns: %{
             route_spec: %{route_id: :app},
             staking: %{wallet_block_number: nil},
             staking_read: nil
           }
         } = socket
       ) do
    case staking_actor(socket) do
      %Human{} = actor ->
        start_wallet_read(socket, socket.assigns.content_generation, fn ->
          Staking.account(actor: actor)
        end)

      nil ->
        socket
    end
  end

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

  defp assign_position_wallet(socket, %{route_id: :stake}),
    do: assign(socket, staking_wallet: position_wallet(socket.assigns))

  defp assign_position_wallet(socket, %{route_id: :redeem}),
    do: assign(socket, redemption_wallet: position_wallet(socket.assigns))

  defp assign_position_wallet(socket, _route_spec), do: socket

  defp load_regent_route(socket, %{route_id: :regent_profile}, %{"slug" => slug}) do
    case Formation.get_public_regent_profile(slug) do
      {:ok, nil} -> raise AshPlatformWeb.NotFoundError
      {:ok, regent} -> assign(socket, regent: regent, regent_status: :ready)
      {:error, _error} -> assign(socket, regent: nil, regent_status: :error)
    end
  end

  defp load_regent_route(socket, _route_spec, _params) do
    regent = socket.assigns.current_regent
    assign(socket, regent: regent, regent_status: if(regent, do: :ready, else: :empty))
  end

  defp assign_page(socket, %{route_id: :regent_profile}, _uri) do
    case socket.assigns.regent_status do
      :ready -> assign(socket, PublicDocuments.page({:regent, socket.assigns.regent}))
      :error -> assign(socket, PublicDocuments.page(:regent_unavailable))
    end
  end

  defp assign_page(socket, _route_spec, uri),
    do: assign(socket, PublicDocuments.page(URI.parse(uri).path))

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
        redemption_notice: %{tone: :error, message: @refresh_failure_notice}
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

  # A lookup past this connection's OpenSea share is shown as unavailable: the
  # manual collection and token ID fields stay open and no wallet action is
  # refused.
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
    case OpenSeaBudget.claim(socket) do
      {:limited, socket} ->
        assign(socket,
          owned_collectibles: Map.put(socket.assigns.owned_collectibles, :status, :unavailable)
        )

      {:ok, socket} ->
        name = {:open_sea, wallet}

        socket
        |> assign(
          open_sea_lookup: name,
          owned_collectibles: loading_collectibles(socket.assigns.owned_collectibles)
        )
        |> start_async(name, fn -> OpenSea.fetch_owned_collectibles(wallet) end)
    end
  end

  defp start_open_sea_lookup(socket, _), do: socket

  defp loading_collectibles(%{status: :idle}),
    do: %{status: :loading, animata: [], regents_club: []}

  defp loading_collectibles(collectibles), do: collectibles
  defp cancel_open_sea_lookup(%{assigns: %{open_sea_lookup: nil}} = socket), do: socket

  defp cancel_open_sea_lookup(socket),
    do: socket |> cancel_async(socket.assigns.open_sea_lookup) |> assign(open_sea_lookup: nil)

  defp parsed_token_id(value) do
    case RedemptionSteps.token_id(value) do
      {:ok, token_id} -> token_id
      :error -> nil
    end
  end

  # Ash wraps a generic action's error in an error class, so the typed refusal
  # the operation boundary returned is read back out of it and the copy can name
  # what actually happened.
  defp refusal(%Ash.Error.Invalid{errors: [%Ash.Error.Invalid.Unavailable{reason: reason} | _]}),
    do: reason

  defp refusal(reason), do: reason

  defp staking_actor(%{assigns: %{access_context: %{principal: {:human, account}}}}),
    do: %Human{human_account_id: account.id}

  defp staking_actor(_socket), do: nil

  # A different wallet's position is not this one's. The contract reading stays
  # exactly as it is while the new wallet is looked up at its own fresh block.
  defp adopt_staking_wallet(socket, wallet),
    do:
      socket
      |> assign(
        staking: forget_wallet_facts(socket.assigns.staking),
        staking_wallet: wallet,
        staking_notice: nil
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
end
