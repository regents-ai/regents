defmodule RegentsWeb.ShellLive do
  @moduledoc """
  One LiveView behind every product-shell page. It keeps what the pages share,
  the route, the signed-in account (through the session hook) and the wallet
  Privy has active, and hands each page's reads, events and messages to the
  feature that owns them: `Account`, `Staking`, `Redemption` and `Gallery`.
  Each feature starts what its page needs when the page opens and lets go of
  it when the page is left.
  """

  use RegentsWeb, :live_view

  import RegentsWeb.Components.Shell

  import RegentsWeb.ShellLive.Identity,
    only: [authenticated?: 1, current_account: 1, linked_wallets: 1]

  import RegentsWeb.StakeLive

  alias Regents.Formation
  alias RegentsWeb.AccountLive
  alias RegentsWeb.AutolaunchLive
  alias RegentsWeb.EventInput
  alias RegentsWeb.ProductLive
  alias RegentsWeb.PublicDocuments
  alias RegentsWeb.RedeemGalleryLive
  alias RegentsWeb.RedeemLive
  alias RegentsWeb.RegentOpsLive
  alias RegentsWeb.RegentProfileLive
  alias RegentsWeb.RouteCatalog
  alias RegentsWeb.ShellLive.{Account, Gallery, OpenSeaBudget, Redemption, Staking}

  @impl true
  def mount(params, _session, socket) do
    route_spec = RouteCatalog.fetch!(socket.assigns.live_action, params)

    {:ok,
     socket
     |> assign(
       route_spec: route_spec,
       route_params: params,
       regent: socket.assigns.current_regent,
       regent_status: if(socket.assigns.current_regent, do: :ready, else: :empty),
       browser_wallet: nil,
       shell_instance: System.unique_integer([:positive, :monotonic])
     )
     |> OpenSeaBudget.init()
     |> Account.init()
     |> Staking.init()
     |> Redemption.init()
     |> Gallery.init()}
  end

  @impl true
  def handle_params(params, uri, socket) do
    route_spec = RouteCatalog.fetch!(socket.assigns.live_action, params)

    {:noreply,
     socket
     |> assign(route_spec: route_spec, route_params: params)
     |> load_regent_route(route_spec, params)
     |> assign_page(route_spec, uri)
     |> Account.route(route_spec)
     |> Staking.route(route_spec)
     |> Redemption.route(route_spec)}
  end

  @impl true
  def handle_async({:agent_activity, _id} = name, result, socket),
    do: {:noreply, Account.settle_activity(socket, name, result)}

  def handle_async({reading, _generation} = name, result, socket)
      when reading in [:staking, :staking_quiet],
      do: {:noreply, Staking.settle(socket, name, result)}

  def handle_async({feature, _key} = name, result, socket)
      when feature in [:redemption, :open_sea],
      do: {:noreply, Redemption.settle(socket, name, result)}

  def handle_async({:gallery_owned, _account_id} = name, result, socket),
    do: {:noreply, Gallery.settle(socket, name, result)}

  @impl true
  def handle_event(event, params, socket) do
    cond do
      Account.handles?(event) -> {:noreply, Account.handle_event(event, params, socket)}
      Redemption.handles?(event) -> {:noreply, Redemption.handle_event(event, params, socket)}
      Staking.handles?(event) -> {:noreply, Staking.handle_event(event, socket)}
      event == "toggle_my_passes" -> {:noreply, Gallery.toggle(socket)}
      # Anything else the page sent is not in a shape this page takes.
      true -> {:noreply, put_flash(socket, :error, EventInput.unreadable())}
    end
  end

  @impl true
  def handle_info({:staking_snapshot, protocol}, socket),
    do: {:noreply, Staking.snapshot(socket, protocol)}

  def handle_info({:staking_snapshot_unavailable, _reason}, socket),
    do: {:noreply, Staking.snapshot_unavailable(socket)}

  def handle_info({:stake_active_wallet, active}, socket),
    do: {:noreply, Staking.active_wallet(socket, active)}

  def handle_info(:stake_step_landed, socket), do: {:noreply, Staking.step_landed(socket)}
  def handle_info(:stake_step_sent, socket), do: {:noreply, Staking.step_sent(socket)}

  def handle_info({:stake_follow, token}, socket),
    do: {:noreply, Staking.follow(socket, token)}

  def handle_info({:redeem_active_wallet, active}, socket),
    do: {:noreply, Redemption.active_wallet(socket, active)}

  def handle_info({:redeem_step_landed, name}, socket),
    do: {:noreply, Redemption.step_landed(socket, name)}

  def handle_info({:ens_lookup_finished, _account_id}, socket),
    do: {:noreply, Account.ens_finished(socket)}

  def handle_info(:agents_changed, socket), do: {:noreply, Account.agents_changed(socket)}

  @impl true
  def render(assigns) do
    ~H"""
    <.shell
      route_spec={@route_spec}
      account_control={@account_control}
      shell_instance={@shell_instance}
    >
      <:content>
        <RegentProfileLive.page
          :if={@route_spec.route_id == :regent_profile}
          regent={@regent}
          status={@regent_status}
        />

        <RegentOpsLive.page
          :if={@route_spec.route_id == :app}
          reading={Staking.reading?(assigns)}
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
          reading={Staking.reading?(assigns)}
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
          reading={Redemption.reading?(assigns)}
          refresh_block={@redemption_refresh_block}
          step={Redemption.step(assigns)}
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

  defp load_regent_route(socket, %{route_id: :regent_profile}, %{"slug" => slug}) do
    case Formation.get_public_regent_profile(slug) do
      {:ok, nil} -> raise RegentsWeb.NotFoundError
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
end
