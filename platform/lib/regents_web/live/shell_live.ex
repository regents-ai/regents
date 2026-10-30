defmodule RegentsWeb.ShellLive do
  @moduledoc """
  One LiveView behind every product-shell page. It keeps what the pages share,
  the route, the signed-in account (through the session hook) and the wallet
  Privy has active, and hands each page's reads, events and messages to the
  feature that owns them: `Account`, `Points`, `Names`, `Staking`,
  `Redemption`, `Gallery` and `PaperProDaily`. Reads go through
  `RegentsWeb.Read`, so only the newest answer for the reader lands.
  Each feature starts what its page needs when the page opens and lets go of
  it when the page is left.
  """

  use RegentsWeb, :live_view

  import RegentsWeb.Components.Shell

  import RegentsWeb.ShellLive.Identity,
    only: [authenticated?: 1, current_account: 1]

  import RegentsWeb.StakeLive

  alias Regents.Formation
  alias RegentsWeb.AccountLive
  alias RegentsWeb.AgentStartLive
  alias RegentsWeb.AutolaunchLive
  alias RegentsWeb.CloakLive
  alias RegentsWeb.CreditsHistoryLive
  alias RegentsWeb.CreditsLive
  alias RegentsWeb.EventInput
  alias RegentsWeb.NamesLive
  alias RegentsWeb.PaperProDailyLive
  alias RegentsWeb.PointsLive
  alias RegentsWeb.ProductLive
  alias RegentsWeb.PublicDocuments
  alias RegentsWeb.Read
  alias RegentsWeb.RedeemGalleryLive
  alias RegentsWeb.RedeemLive
  alias RegentsWeb.RegentOpsLive
  alias RegentsWeb.RegentProfileLive
  alias RegentsWeb.RouteCatalog

  alias RegentsWeb.ShellLive.{
    Account,
    Gallery,
    Names,
    PaperProDaily,
    Points,
    Redemption,
    Staking
  }

  @impl true
  def mount(params, session, socket) do
    route_spec = RouteCatalog.fetch!(socket.assigns.live_action, params)

    {:ok,
     socket
     |> assign(
       client_tag: Map.fetch!(session, "client_tag"),
       route_spec: route_spec,
       route_params: params,
       regent: socket.assigns.current_regent,
       regent_status: if(socket.assigns.current_regent, do: :ready, else: :empty),
       browser_wallet: nil,
       blog_posts: [],
       blog_post: nil,
       shell_instance: System.unique_integer([:positive, :monotonic]),
       credits: %Read{}
     )
     |> follow_credits()
     |> Account.init()
     |> Points.init()
     |> Names.init()
     |> Staking.init()
     |> Redemption.init()
     |> Gallery.init()
     |> PaperProDaily.init()}
  end

  @impl true
  def handle_params(params, uri, socket) do
    route_spec = RouteCatalog.fetch!(socket.assigns.live_action, params)

    {:noreply,
     socket
     |> assign(route_spec: route_spec, route_params: params)
     |> load_regent_route(route_spec, params)
     |> load_blog_route(route_spec, params)
     |> assign_page(route_spec, uri)
     |> Account.route(route_spec)
     |> Points.route(route_spec)
     |> Names.route(route_spec)
     |> Staking.route(route_spec)
     |> Redemption.route(route_spec)
     |> PaperProDaily.route(route_spec)
     |> read_credits()}
  end

  @impl true
  def handle_async({Read, _name, _generation} = name, result, socket),
    do: {:noreply, Read.settle(socket, name, result)}

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
      Account.handles?(event) ->
        {:noreply, Account.handle_event(event, params, socket)}

      Names.handles?(event) ->
        {:noreply, Names.handle_event(event, params, socket)}

      Redemption.handles?(event) ->
        {:noreply, Redemption.handle_event(event, params, socket)}

      Staking.handles?(event) ->
        {:noreply, Staking.handle_event(event, socket)}

      PaperProDaily.handles?(event) ->
        {:noreply, PaperProDaily.handle_event(event, params, socket)}

      event == "toggle_my_passes" ->
        {:noreply, Gallery.toggle(socket)}

      # Anything else the page sent is not in a shape this page takes.
      true ->
        {:noreply, put_flash(socket, :error, EventInput.unreadable())}
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

  # The session has already read the account again, so every place showing the
  # wallet's name shows the answer.
  def handle_info({:ens_lookup_finished, _account_id}, socket), do: {:noreply, socket}

  def handle_info(:agents_changed, socket), do: {:noreply, Account.agents_changed(socket)}

  # A points award or correction landed for this account; the Points page follows.
  def handle_info(%{topic: "points:" <> _}, socket), do: {:noreply, Points.changed(socket)}

  # The balance changed on this or any Regent site: a purchase, a gift, a spend.
  # The header, the Buy Credits panel, the Account page and the Credits history
  # follow. Every page change reads the balance again too.
  def handle_info(:credits_changed, socket),
    do: {:noreply, socket |> read_credits() |> Account.credits_changed()}

  def handle_info(:publication_midnight, socket), do: {:noreply, PaperProDaily.midnight(socket)}

  @impl true
  def render(assigns) do
    ~H"""
    <.shell
      route_spec={@route_spec}
      account_control={@account_control}
      shell_instance={@shell_instance}
      credits={signed_in_credits(@access_context, @credits)}
    >
      <:credits_panel :if={signed_in_credits(@access_context, @credits)}>
        <.live_component
          module={RegentsWeb.CreditsPanel}
          id="credits-panel"
          lease={@session_lease}
          account={current_account(@access_context)}
          credits={@credits}
          client_tag={@client_tag}
        />
      </:credits_panel>
      <:agents :if={current_account(@access_context)}>
        <.live_component
          module={RegentsWeb.MenuAgents}
          id="shell-agents"
          lease={@session_lease}
          account={current_account(@access_context)}
        />
      </:agents>
      <:content>
        <.link
          :if={@route_spec.route_id == :blog && Regents.Blog.admin?(current_account(@access_context))}
          class="rg-button"
          patch="/admin/articles"
        >New Article →</.link>
        <Regent.Blog.gallery
          :if={@route_spec.route_id == :blog and @blog_posts != []}
          posts={@blog_posts}
          site="Regents Labs"
          name="Articles"
          path="/articles"
        />
        <%!-- Before the first article, point readers at what is new every day. --%>
        <section
          :if={@route_spec.route_id == :blog and @blog_posts == []}
          class="rg-blog rg-sheet rg-blog--gallery"
          aria-labelledby="blog-title"
        >
          <header class="rg-blog__intro">
            <p class="rg-blog__eyebrow">Articles</p>
            <h1 id="blog-title">Latest updates from Regents Labs.</h1>
          </header>
          <div class="rg-blog__empty">
            <h2>The first article is on its way.</h2>
            <p>
              Until then, <.link navigate="/paper-pro-daily">Daily Research</.link>
              has new papers every day.
            </p>
          </div>
        </section>

        <%!-- The post is static; retain the shared renderer's client-side math enhancement. --%>
        <div
          :if={@route_spec.route_id == :blog_post}
          id={"blog-post-#{@blog_post.slug}"}
          phx-update="ignore"
        >
          <Regent.Blog.article post={@blog_post} name="Articles" path="/articles" />
        </div>

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

        <AccountLive.profile
          :if={@route_spec.route_id == :account}
          signed_out_reason={@signed_out_reason}
          lease={@session_lease}
          account={current_account(@access_context)}
          account_control={@account_control}
          credits_read={@credits}
        />

        <PointsLive.page
          :if={@route_spec.route_id == :points}
          signed_out_reason={@signed_out_reason}
          account={current_account(@access_context)}
          points={@points}
          bonus={@points_bonus}
          earning={@points_earning}
        />

        <CreditsHistoryLive.page
          :if={@route_spec.route_id == :credits}
          signed_out_reason={@signed_out_reason}
          account={current_account(@access_context)}
          history={@credits_history}
        />
        <CreditsLive.agent_spending
          :if={@route_spec.route_id == :credits && current_account(@access_context)}
          lease={@session_lease}
          account={current_account(@access_context)}
          agents={@spending_agents}
        />

        <AccountLive.wallets
          :if={@route_spec.route_id == :wallets}
          signed_out_reason={@signed_out_reason}
          account={current_account(@access_context)}
          sign_in_wallets={@sign_in_wallets}
        />

        <AccountLive.connections
          :if={@route_spec.route_id == :connections}
          signed_out_reason={@signed_out_reason}
          account={current_account(@access_context)}
          verified_connections={@verified_connections}
          verified_connections_notice={@verified_connections_notice}
        />

        <NamesLive.page
          :if={@route_spec.route_id == :names}
          signed_out_reason={@signed_out_reason}
          account={current_account(@access_context)}
          names={@names}
          stream={@streams.names}
          claims={@name_claims}
          claim_name={@claim_name}
        />

        <.page
          :if={@route_spec.route_id == :stake}
          lease={@session_lease}
          staking={@staking}
          status={@staking_status}
          wallet={@staking_wallet}
          account={current_account(@access_context)}
          notice={@staking_notice}
          reading={Staking.reading?(assigns)}
          shared_reading={@staking_shared_reading}
        />

        <.live_component
          :if={@route_spec.route_id == :redeem}
          module={RedeemLive}
          id="animata-redemption"
          lease={@session_lease}
          redemption={@redemption}
          status={@redemption_status}
          wallet={@redemption_wallet}
          account={current_account(@access_context)}
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
        <PaperProDailyLive.page
          :if={@route_spec.route_id == :paper_pro_daily}
          page_markdown={@page_markdown}
          research_list={@research_list}
          research_list_expanded?={@research_list_expanded?}
          streams={@streams}
          more?={@more?}
          shown={@shown}
        />
        <RegentsWeb.LiteratureHTML.show
          :if={@route_spec.route_id == :literature}
          books={RegentsWeb.Literature.books()}
        />

        <AgentStartLive.page
          :if={@route_spec.route_id == :agent_start}
          agent={@route_params["agent"]}
        />

        <ProductLive.page
          :if={@route_spec.route_id in [:techtree, :patchbay, :keyfleet]}
          product={@route_spec.route_id}
        />

        <CloakLive.page :if={@route_spec.route_id == :cloak} />
        <CloakLive.guide :if={@route_spec.route_id == :cloak_guide} />

        <CreditsLive.refunds :if={@route_spec.route_id == :credits_refunds} />

        <CreditsLive.admin
          :if={@route_spec.route_id == :credits_admin}
          lease={@session_lease}
          account={current_account(@access_context)}
          signed_out_reason={@signed_out_reason}
        />

        <.live_component
          :if={
            @route_spec.route_id == :articles_admin &&
              Regents.Blog.admin?(current_account(@access_context))
          }
          module={RegentsWeb.ArticleEditor}
          id="article-editor"
          lease={@session_lease}
          account={current_account(@access_context)}
        />
        <Regent.Account.signed_out
          :if={@route_spec.route_id == :articles_admin && is_nil(current_account(@access_context))}
          id="article-editor-signed-out"
          reason={@signed_out_reason}
        >
          <:sign_in>
            <Regent.Primitives.button type="button" data-account-target="sign-in">
              Sign in
            </Regent.Primitives.button>
          </:sign_in>
        </Regent.Account.signed_out>
        <Regent.Primitives.notice
          :if={
            @route_spec.route_id == :articles_admin && current_account(@access_context) &&
              !Regents.Blog.admin?(current_account(@access_context))
          }
          tone="error"
        >
          Your editor access has ended. Reload and sign in again.
        </Regent.Primitives.notice>
      </:content>
    </.shell>
    """
  end

  # A session that ends while the page is open takes the balance and the panel
  # with it at once; the balance read at mount is never shown to nobody. While
  # signed in, the panel and its wallet buttons are there whatever the reading.
  defp signed_in_credits(access_context, credits),
    do:
      if(authenticated?(access_context) and RegentsWeb.Plugs.LaunchGate.app_surfaces_enabled?(),
        do: credits
      )

  # Signing in or out reloads the page, so the account followed here is the
  # page's own for as long as it is open.
  defp follow_credits(socket) do
    with true <- connected?(socket),
         %{privy_user_id: id} <- current_account(socket.assigns.access_context) do
      Phoenix.PubSub.subscribe(Regents.PubSub, RegentCredits.topic(id))
    end

    socket
  end

  # A read that fails leaves the page standing and says so where the balance is
  # shown: a failed refresh keeps the last balance as stale, and a first read
  # that fails is an error, never zero.
  defp read_credits(socket) do
    case current_account(socket.assigns.access_context) do
      nil ->
        Read.clear(socket, :credits)

      %{privy_user_id: id} ->
        Read.now(socket, :credits, id, fn -> {:ok, RegentCredits.balance(id)} end)
    end
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

  defp load_blog_route(socket, %{route_id: :blog}, _params),
    do: assign(socket, blog_posts: RegentsWeb.Blog.all(), blog_post: nil)

  defp load_blog_route(socket, %{route_id: :blog_post}, %{"slug" => slug}) do
    case RegentsWeb.Blog.get(slug) do
      nil -> raise RegentsWeb.NotFoundError
      post -> assign(socket, blog_posts: [], blog_post: post)
    end
  end

  defp load_blog_route(socket, _spec, _params), do: assign(socket, blog_posts: [], blog_post: nil)

  defp assign_page(socket, %{route_id: :regent_profile}, _uri) do
    case socket.assigns.regent_status do
      :ready -> assign(socket, PublicDocuments.page({:regent, socket.assigns.regent}))
      :error -> assign(socket, PublicDocuments.page(:regent_unavailable))
    end
  end

  defp assign_page(socket, %{route_id: :blog_post}, _uri),
    do: assign(socket, PublicDocuments.page({:blog_post, socket.assigns.blog_post}))

  defp assign_page(socket, _route_spec, uri),
    do: assign(socket, PublicDocuments.page(URI.parse(uri).path))
end
