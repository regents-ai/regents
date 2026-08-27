defmodule AshPlatformWeb.ShellLive do
  use AshPlatformWeb, :live_view

  import AshPlatformWeb.Components.Shell
  import AshPlatformWeb.RedeemLive
  import AshPlatformWeb.StakeLive

  alias AshPlatform.{
    Accounts,
    Autolaunch,
    ContentCoordinator,
    Discussions,
    Formation,
    OpenSea,
    Redemption,
    Staking,
    Techtree
  }

  alias AshPlatform.Actors.Human
  alias AshPlatform.Techtree.{Payload, Provenance, UpliftReport}
  alias AshPlatform.WalletActions.Address
  alias AshPlatformWeb.AutolaunchLive
  alias AshPlatformWeb.FormationLive
  alias AshPlatformWeb.Plugs.LaunchGate
  alias AshPlatformWeb.RegentOpsLive
  alias AshPlatformWeb.RegentProfileLive
  alias AshPlatformWeb.RouteCatalog
  alias AshPlatformWeb.SettingsLive
  alias AshPlatformWeb.TechtreeLive

  @identity_providers %{"x" => :x, "github" => :github, "farcaster" => :farcaster}

  @impl true
  def mount(params, _session, socket) do
    route_spec = RouteCatalog.fetch!(socket.assigns.live_action, params)

    case authorize_route(socket, route_spec) do
      {:redirect, socket} ->
        {:ok, socket}

      {:ok, socket} ->
        mount_authorized(params, route_spec, socket)
    end
  end

  defp mount_authorized(params, route_spec, socket) do
    {:ok,
     assign(socket,
       app_targets: open_app_targets(),
       content: nil,
       content_error: nil,
       content_async_name: nil,
       content_generation: 0,
       content_status: :loading,
       comments: [],
       comments_status: :ready,
       comment_reactions: %{},
       comment_target: nil,
       comment_topic: nil,
       comment_request_id: Ash.UUID.generate(),
       comment_draft: "",
       comment_notice: nil,
       verified_connections: [],
       verified_connections_notice: nil,
       comment_admin?: Discussions.admin_actor?(human_actor(socket)),
       route_params: params,
       autolaunch_featured_auctions: [],
       autolaunch_recent_auctions: [],
       autolaunch_top_tokens: [],
       autolaunch_graduated_tokens: [],
       autolaunch_records: [],
       autolaunch_record: nil,
       autolaunch_subject_tokens: [],
       autolaunch_subject_actions: [],
       autolaunch_subject_settlements: [],
       autolaunch_bid_positions: [],
       autolaunch_returnable_positions: [],
       autolaunch_claimed_token_positions: [],
       autolaunch_launch_drafts: [],
       autolaunch_draft_values: AutolaunchLive.blank_draft_fields(),
       autolaunch_draft_errors: %{},
       autolaunch_draft_revision: nil,
       autolaunch_draft_notice: nil,
       autolaunch_status: :loading,
       techtree_trees: [],
       techtree_tree: nil,
       techtree_nodes: [],
       techtree_edges: [],
       techtree_node: nil,
       techtree_provenance: nil,
       techtree_uplift_report: nil,
       techtree_payload_status: :not_available,
       techtree_notebook_artifact: nil,
       techtree_status: :loading,
       regent: socket.assigns.current_regent,
       regent_status: if(socket.assigns.current_regent, do: :ready, else: :empty),
       presentation: initial_presentation(route_spec),
       redemption: nil,
       redemption_collection: "animata_i",
       redemption_token_id: "",
       redemption_notice: nil,
       redemption_read: nil,
       redemption_generation: 0,
       redemption_wallet: nil,
       redemption_status: :loading,
       owned_collectibles: %{status: :idle, animata: [], regents_club: []},
       open_sea_lookup: nil,
       staking: nil,
       staking_action: "stake",
       staking_amount: "",
       staking_wallet: nil,
       staking_notice: nil,
       staking_read: nil,
       staking_status: :loading,
       route_spec: route_spec,
       shell_instance: System.unique_integer([:positive, :monotonic])
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    route_spec = RouteCatalog.fetch!(socket.assigns.live_action, params)

    case authorize_route(socket, route_spec) do
      {:redirect, socket} -> {:noreply, socket}
      {:ok, socket} -> handle_authorized_params(params, route_spec, socket)
    end
  end

  defp handle_authorized_params(params, route_spec, socket) do
    generation = socket.assigns.content_generation + 1

    socket = cancel_content(socket)

    socket =
      assign(socket,
        content: nil,
        content_async_name: nil,
        content_error: nil,
        content_generation: generation,
        content_status: :loading,
        presentation: initial_presentation(route_spec),
        route_spec: route_spec,
        route_params: params
      )

    socket =
      socket
      |> load_regent_route(route_spec, params)
      |> load_techtree_route(route_spec, params)
      |> load_autolaunch_route(route_spec, params)
      |> load_verified_connections(route_spec)
      |> load_comments_route(route_spec)

    cond do
      route_spec.route_id == :settings ->
        {:noreply, assign(socket, content_status: :ready)}

      content_route?(route_spec) and connected?(socket) ->
        start_content(socket, route_spec, params, generation)

      content_route?(route_spec) ->
        {:noreply, socket}

      connected?(socket) ->
        {:noreply,
         socket
         |> assign(content_status: :ready)
         |> maybe_start_staking(route_spec, generation)
         |> maybe_start_redemption(route_spec, generation)}

      true ->
        {:noreply, assign(socket, content_status: :ready)}
    end
  end

  # The Autolaunch switch decides what this page offers; the route catalog it
  # reads from is unchanged.
  defp open_app_targets, do: Enum.filter(RouteCatalog.app_targets(), &app_target_open?/1)

  defp app_target_open?(%{app_id: :autolaunch}), do: LaunchGate.autolaunch_surfaces_enabled?()
  defp app_target_open?(_target), do: true

  defp authorize_route(
         %{assigns: %{access_context: %{principal: :anonymous}}} = socket,
         %{route_id: route_id}
       )
       when route_id in [:settings, :autolaunch_holdings] do
    {:redirect, redirect(socket, to: "/")}
  end

  defp authorize_route(socket, _route_spec), do: {:ok, socket}

  defp start_content(socket, route_spec, params, generation) do
    name = {:content, generation}

    socket =
      socket
      |> assign(content_async_name: name)
      |> start_async(name, fn ->
        ContentCoordinator.load(generation, route_spec, params)
      end)

    {:noreply,
     socket
     |> maybe_start_staking(route_spec, generation)
     |> maybe_start_redemption(route_spec, generation)}
  end

  defp content_route?(%{route_id: :regent_profile}), do: true
  defp content_route?(_route_spec), do: false

  @impl true
  def handle_async(
        {:content, generation},
        {:ok, {generation, result}},
        %{assigns: %{content_generation: generation}} = socket
      ) do
    case result do
      {:ok, content} ->
        {:noreply,
         assign(socket,
           content: content,
           content_status: :ready,
           content_async_name: nil
         )}

      {:error, reason} ->
        {:noreply, content_failed(socket, reason)}
    end
  end

  def handle_async({:content, _generation}, {:ok, _result}, socket), do: {:noreply, socket}

  def handle_async(
        {:content, generation},
        {:exit, reason},
        %{assigns: %{content_generation: generation}} = socket
      ) do
    {:noreply, content_failed(socket, reason)}
  end

  def handle_async({:content, _generation}, {:exit, _reason}, socket), do: {:noreply, socket}

  def handle_async(
        {:staking, generation} = name,
        {:ok, {generation, {:ok, staking}}},
        %{assigns: %{content_generation: generation}} = socket
      ) do
    {:noreply,
     socket
     |> dismiss_settled_staking(name)
     |> release_staking_read(name)
     |> assign(staking: staking, staking_status: :ready)}
  end

  # Only membership can unmake an active wallet, so the refusal decides what this
  # failure means before anything on the page is cleared.
  def handle_async(
        {:staking, generation} = name,
        {:ok, {generation, {:error, reason}}},
        %{
          assigns: %{
            content_generation: generation,
            route_spec: %{route_id: :stake},
            staking_wallet: wallet
          }
        } = socket
      )
      when not is_nil(wallet) do
    {:noreply,
     socket
     |> release_staking_read(name)
     |> staking_read_failed(refusal(reason), generation)}
  end

  def handle_async(
        {:staking, generation} = name,
        {:ok, {generation, {:error, _reason}}},
        %{assigns: %{content_generation: generation}} = socket
      ) do
    {:noreply,
     socket |> release_staking_read(name) |> assign(staking: nil, staking_status: :error)}
  end

  # A read that crashed answered nothing about Base, so it is the same
  # unavailable page: the submitted transaction stays on screen behind the same
  # read-only retry, which this releases rather than withdraws.
  def handle_async(
        {:staking, generation} = name,
        {:exit, _reason},
        %{assigns: %{content_generation: generation, route_spec: %{route_id: :stake}}} = socket
      ) do
    {:noreply,
     socket |> release_staking_read(name) |> assign(staking: nil, staking_status: :error)}
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
    {:noreply,
     socket
     |> dismiss_settled_redemption(name)
     |> release_redemption_read(name)
     |> assign(redemption: redemption, redemption_status: :ready)
     |> start_open_sea_lookup(generation)}
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

  # A read that crashed answered nothing about Base, so it is the same
  # unavailable page: the confirmed redemption stays on screen behind the same
  # read-only retry, which this releases rather than withdraws.
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
    {:noreply,
     socket
     |> release_redemption_read(name)
     |> assign(redemption: nil, redemption_status: :error)}
  end

  # A read whose page has since moved on still releases its own marker, so the
  # refresh control is never left disabled by a read nobody is waiting for.
  def handle_async({:redemption, _generation} = name, _result, socket),
    do: {:noreply, release_redemption_read(socket, name)}

  def handle_async(
        {:open_sea, wallet, generation} = name,
        {:ok, {:ok, items}},
        %{
          assigns: %{
            route_spec: %{route_id: :redeem},
            redemption_wallet: wallet,
            redemption_generation: generation,
            open_sea_lookup: name
          }
        } = socket
      ) do
    status = if items.animata == [] and items.regents_club == [], do: :empty, else: :ready

    {:noreply,
     assign(socket, open_sea_lookup: nil, owned_collectibles: Map.put(items, :status, status))}
  end

  def handle_async(
        {:open_sea, _wallet, _generation} = name,
        _result,
        %{assigns: %{open_sea_lookup: name}} = socket
      ),
      do:
        {:noreply,
         assign(socket,
           open_sea_lookup: nil,
           owned_collectibles: %{status: :unavailable, animata: [], regents_club: []}
         )}

  def handle_async({:open_sea, _, _}, _result, socket), do: {:noreply, socket}

  @impl true
  def handle_event(
        "post_comment",
        %{"comment" => %{"body" => body, "client_request_id" => client_request_id}},
        socket
      ) do
    with %Human{} = actor <- human_actor(socket),
         %{type: target_type, id: target_id} <- socket.assigns.comment_target,
         {:ok, _comment} <-
           Discussions.post_comment(
             target_type,
             target_id,
             body,
             client_request_id,
             actor: actor
           ) do
      {:noreply,
       socket
       |> assign(
         comment_draft: "",
         comment_request_id: Ash.UUID.generate(),
         comment_notice: %{tone: :success, message: "Comment posted."}
       )
       |> reload_comments()}
    else
      _ ->
        {:noreply,
         assign(socket,
           comment_draft: body,
           comment_notice: %{
             tone: :error,
             message: "That comment could not be posted. Check its length and formatting."
           }
         )}
    end
  end

  # A draft event that arrives while Autolaunch is closed is answered before any
  # actor is built or any record is read or written.
  def handle_event(event, params, socket)
      when event in ["create_launch_draft", "revise_launch_draft"] do
    if LaunchGate.autolaunch_surfaces_enabled?(),
      do: handle_draft_event(event, params, socket),
      else:
        {:noreply,
         assign(socket,
           autolaunch_draft_notice: %{
             tone: :error,
             message: "This part of Regent isn't open yet."
           }
         )}
  end

  def handle_event("delete_comment", %{"id" => id}, socket) do
    with %Human{} = actor <- human_actor(socket),
         comment when not is_nil(comment) <- Enum.find(socket.assigns.comments, &(&1.id == id)),
         {:ok, _deleted} <- Discussions.delete_comment(comment, actor: actor) do
      {:noreply,
       socket
       |> assign(comment_notice: %{tone: :success, message: "Comment deleted."})
       |> reload_comments()}
    else
      _ ->
        {:noreply,
         assign(socket,
           comment_notice: %{tone: :error, message: "That comment could not be deleted."}
         )}
    end
  end

  def handle_event(
        "react_comment",
        %{"id" => comment_id, "reaction" => reaction},
        %{assigns: %{comment_target: %{type: :techtree_node}}} = socket
      ) do
    with %Human{} = actor <- human_actor(socket),
         {:ok, value} <- reaction_value(reaction),
         comment when not is_nil(comment) <-
           Enum.find(socket.assigns.comments, &(&1.id == comment_id)),
         :ok <- toggle_comment_reaction(comment, value, actor) do
      {:noreply,
       socket
       |> assign(comment_notice: %{tone: :success, message: "Reaction updated."})
       |> reload_comment_reactions()}
    else
      _ ->
        {:noreply,
         assign(socket,
           comment_notice: %{tone: :error, message: "That reaction could not be updated."}
         )}
    end
  end

  def handle_event("react_comment", _params, socket) do
    {:noreply,
     assign(socket,
       comment_notice: %{tone: :error, message: "Reactions are available on Techtree comments."}
     )}
  end

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
         verified_connections_notice: %{
           tone: :info,
           message: "Complete the connection in the window that opens."
         }
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

  def handle_event("refresh_verified_connections", params, socket) do
    notice =
      case params do
        %{"error" => "already-connected"} ->
          %{
            tone: :error,
            message: "That account is already connected to another Regent account."
          }

        %{"error" => error} when is_binary(error) and error != "" ->
          %{tone: :error, message: "That connection couldn’t be verified. Try again."}

        _params ->
          %{tone: :success, message: "Verified connections updated."}
      end

    {:noreply,
     socket
     |> reload_verified_connections()
     |> assign(verified_connections_notice: notice)}
  end

  def handle_event(event, params, socket)
      when event in [
             "redemption_active_wallet",
             "redemption_selection_changed",
             "prepare_redemption",
             "refresh_redemption",
             "select_owned_animata"
           ],
      do: handle_redemption_event(event, params, socket)

  def handle_event(
        "staking_active_wallet",
        params,
        %{assigns: %{route_spec: %{route_id: :stake}}} = socket
      ) do
    wallet =
      if authenticated?(socket.assigns.access_context), do: normalized_wallet(params["address"])

    if wallet == socket.assigns.staking_wallet,
      do: {:noreply, socket},
      else: {:noreply, adopt_staking_wallet(socket, wallet)}
  end

  def handle_event("staking_active_wallet", _params, socket), do: {:noreply, socket}

  def handle_event("select_staking_action", %{"mode" => mode}, socket)
      when mode in ["stake", "unstake"],
      do:
        {:noreply, assign(socket, staking_action: mode, staking_amount: "", staking_notice: nil)}

  def handle_event("select_staking_action", _params, socket), do: {:noreply, socket}

  def handle_event("fill_staking_amount", %{"portion" => portion}, socket)
      when portion in ["half", "max"] do
    amount = Staking.spendable(socket.assigns.staking, socket.assigns.staking_action)

    {:noreply,
     assign(socket, staking_amount: token_amount(portioned(amount, portion)), staking_notice: nil)}
  end

  def handle_event("fill_staking_amount", _params, socket), do: {:noreply, socket}

  def handle_event("staking_amount_changed", %{"amount" => amount}, socket),
    do: {:noreply, assign(socket, staking_amount: amount, staking_notice: nil)}

  def handle_event("prepare_staking", params, socket) do
    case prepare_staking(
           params["action"],
           params["amount"] || socket.assigns.staking_amount,
           socket
         ) do
      {:ok, envelope} ->
        {:noreply,
         socket
         |> assign(staking_notice: nil)
         |> push_event("staking:wallet-action", %{envelope: envelope})}

      {:error, reason} ->
        {:noreply,
         assign(socket,
           staking_notice: %{tone: :error, message: staking_preparation_error(refusal(reason))}
         )}
    end
  end

  def handle_event("refresh_staking", _params, socket),
    do: {:noreply, start_staking_read(socket, socket.assigns.content_generation)}

  @impl true
  def handle_info(
        {:comments_changed, target_type, target_id},
        %{assigns: %{comment_target: %{type: target_type, id: target_id}}} = socket
      ) do
    notice = socket.assigns.comment_notice || %{tone: :info, message: "Comments updated."}
    {:noreply, socket |> assign(comment_notice: notice) |> reload_comments()}
  end

  def handle_info({:comments_changed, _target_type, _target_id}, socket), do: {:noreply, socket}

  def handle_info(
        {:comment_reactions_changed, target_type, target_id},
        %{assigns: %{comment_target: %{type: target_type, id: target_id}}} = socket
      ) do
    notice = socket.assigns.comment_notice || %{tone: :info, message: "Reactions updated."}
    {:noreply, socket |> assign(comment_notice: notice) |> reload_comment_reactions()}
  end

  def handle_info({:comment_reactions_changed, _target_type, _target_id}, socket),
    do: {:noreply, socket}

  defp handle_draft_event("create_launch_draft", %{"launch_draft" => submitted}, socket) do
    values = Map.take(submitted, AutolaunchLive.draft_field_params())

    with %Human{} = actor <- human_actor(socket),
         {:ok, _draft} <- Autolaunch.create_launch_draft(values, actor: actor),
         {:ok, drafts} <- Autolaunch.list_my_launch_drafts(actor: actor) do
      {:noreply,
       assign(socket,
         autolaunch_launch_drafts: drafts,
         autolaunch_draft_values: AutolaunchLive.blank_draft_fields(),
         autolaunch_draft_errors: %{},
         autolaunch_draft_notice: %{
           tone: :success,
           message: "Draft saved. Nothing has been published and no money has moved."
         }
       )}
    else
      error ->
        {:noreply,
         assign(socket,
           autolaunch_draft_values: values,
           autolaunch_draft_errors: draft_field_errors(error),
           autolaunch_draft_notice: %{
             tone: :error,
             message: "That draft could not be saved. Check the details marked below."
           }
         )}
    end
  end

  defp handle_draft_event(
         "revise_launch_draft",
         %{"draft_id" => draft_id, "launch_draft" => submitted},
         socket
       ) do
    values = Map.take(submitted, AutolaunchLive.draft_field_params())

    with %Human{} = actor <- human_actor(socket),
         draft when not is_nil(draft) <-
           Enum.find(socket.assigns.autolaunch_launch_drafts, &(&1.id == draft_id)),
         {:ok, _draft} <- Autolaunch.revise_launch_draft(draft, values, actor: actor),
         {:ok, drafts} <- Autolaunch.list_my_launch_drafts(actor: actor) do
      {:noreply,
       assign(socket,
         autolaunch_launch_drafts: drafts,
         autolaunch_draft_revision: nil,
         autolaunch_draft_notice: %{
           tone: :success,
           message: "Draft updated. Nothing has been published and no money has moved."
         }
       )}
    else
      error ->
        {:noreply,
         assign(socket,
           autolaunch_draft_revision: %{
             id: draft_id,
             values: values,
             errors: draft_field_errors(error)
           },
           autolaunch_draft_notice: %{
             tone: :error,
             message: "That draft could not be updated. Check the details marked below."
           }
         )}
    end
  end

  defp draft_field_errors({:error, %Ash.Error.Invalid{errors: errors}}) do
    params = AutolaunchLive.draft_field_params()

    for %{field: field} = error <- errors,
        to_string(field) in params,
        into: %{},
        do: {to_string(field), draft_field_message(error)}
  end

  defp draft_field_errors(_error), do: %{}

  defp draft_field_message(%Ash.Error.Changes.Required{}), do: "is required"
  defp draft_field_message(%{message: message}), do: message

  defp handle_redemption_event("redemption_active_wallet", params, socket) do
    wallet =
      if authenticated?(socket.assigns.access_context), do: normalized_wallet(params["address"])

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

    {:noreply, start_redemption_read(socket)}
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

    {:noreply, start_redemption_read(socket)}
  end

  defp handle_redemption_event("prepare_redemption", %{"action" => action}, socket) do
    case prepare_redemption(action, socket) do
      {:ok, envelope} ->
        {:noreply,
         socket
         |> assign(redemption_notice: nil)
         |> push_event("redemption:wallet-action", %{envelope: envelope})}

      {:error, reason} ->
        {:noreply,
         assign(socket,
           redemption_notice: %{tone: :error, message: preparation_error(refusal(reason))}
         )}
    end
  end

  defp handle_redemption_event("refresh_redemption", _params, socket),
    do: {:noreply, start_redemption_read(socket)}

  @impl true
  def render(assigns) do
    ~H"""
    <.shell
      route_spec={@route_spec}
      app_targets={@app_targets}
      account_control={@account_control}
      content_status={@content_status}
      presentation={@presentation}
      shell_instance={@shell_instance}
    >
      <:content>
        <AutolaunchLive.page
          :if={
            @route_spec.route_id in [
              :autolaunch,
              :autolaunch_auctions,
              :autolaunch_auction,
              :autolaunch_tokens,
              :autolaunch_token,
              :autolaunch_launches,
              :autolaunch_launch,
              :autolaunch_subjects,
              :autolaunch_subject,
              :autolaunch_holdings,
              :autolaunch_create
            ]
          }
          route_spec={@route_spec}
          params={@route_params}
          account_control={@account_control}
          featured_auctions={@autolaunch_featured_auctions}
          recent_auctions={@autolaunch_recent_auctions}
          top_tokens={@autolaunch_top_tokens}
          graduated_tokens={@autolaunch_graduated_tokens}
          records={@autolaunch_records}
          record={@autolaunch_record}
          subject_tokens={@autolaunch_subject_tokens}
          subject_actions={@autolaunch_subject_actions}
          subject_settlements={@autolaunch_subject_settlements}
          bid_positions={@autolaunch_bid_positions}
          returnable_positions={@autolaunch_returnable_positions}
          claimed_token_positions={@autolaunch_claimed_token_positions}
          session_lease={@session_lease}
          launch_drafts={@autolaunch_launch_drafts}
          draft_values={@autolaunch_draft_values}
          draft_errors={@autolaunch_draft_errors}
          draft_revision={@autolaunch_draft_revision}
          draft_notice={@autolaunch_draft_notice}
          regent={@regent}
          status={@autolaunch_status}
          comments={@comments}
          comments_status={@comments_status}
          comment_notice={@comment_notice}
          comment_request_id={@comment_request_id}
          comment_draft={@comment_draft}
          current_human_id={current_human_id(@access_context)}
          comment_admin={@comment_admin?}
        />

        <TechtreeLive.page
          :if={@route_spec.route_id in [:techtree, :techtree_tree, :techtree_node]}
          route_spec={@route_spec}
          params={@route_params}
          trees={@techtree_trees}
          tree={@techtree_tree}
          nodes={@techtree_nodes}
          edges={@techtree_edges}
          node={@techtree_node}
          provenance={@techtree_provenance}
          uplift_report={@techtree_uplift_report}
          payload_status={@techtree_payload_status}
          status={@techtree_status}
          presentation={@presentation}
          comments={@comments}
          comments_status={@comments_status}
          comment_notice={@comment_notice}
          comment_request_id={@comment_request_id}
          comment_draft={@comment_draft}
          current_human_id={current_human_id(@access_context)}
          comment_admin={@comment_admin?}
          comment_reactions={@comment_reactions}
          notebook_artifact={@techtree_notebook_artifact}
        />

        <FormationLive.page :if={@route_spec.route_id == :formation} />

        <RegentProfileLive.page
          :if={@route_spec.route_id == :regent_profile}
          regent={@regent}
          status={@regent_status}
        />

        <RegentOpsLive.page
          :if={@route_spec.route_id == :app}
          staking={@staking}
          status={@staking_status}
          account_control={@account_control}
          account={current_account(@access_context)}
        />

        <SettingsLive.page
          :if={@route_spec.route_id == :settings}
          verified_connections={@verified_connections}
          verified_connections_notice={@verified_connections_notice}
        />

        <.page
          :if={@route_spec.route_id == :stake}
          staking={@staking}
          status={@staking_status}
          authenticated={authenticated?(@access_context)}
          wallet={@staking_wallet}
          action={@staking_action}
          amount={@staking_amount}
          notice={@staking_notice}
          reading={staking_reading?(assigns)}
          spendable={Staking.spendable(@staking, @staking_action)}
          amount_notice={staking_amount_notice(assigns)}
          available_claims={Staking.available_claims(@staking)}
        />

        <.redemption_page
          :if={@route_spec.route_id == :redeem}
          redemption={@redemption}
          status={@redemption_status}
          authenticated={authenticated?(@access_context)}
          wallet={@redemption_wallet}
          collection={@redemption_collection}
          token_id={@redemption_token_id}
          notice={@redemption_notice}
          reading={redemption_reading?(assigns)}
          step={@redemption && Redemption.next_step(@redemption, @redemption_wallet)}
          owned_collectibles={@owned_collectibles}
        />

        <section
          :if={
            @route_spec.route_id not in [
              :app,
              :settings,
              :formation,
              :stake,
              :redeem,
              :techtree,
              :techtree_tree,
              :techtree_node,
              :autolaunch,
              :autolaunch_auctions,
              :autolaunch_auction,
              :autolaunch_tokens,
              :autolaunch_token,
              :autolaunch_launches,
              :autolaunch_launch,
              :autolaunch_subjects,
              :autolaunch_subject,
              :autolaunch_holdings,
              :autolaunch_create,
              :regent_profile
            ] &&
              @content_status == :loading
          }
          class="shell-status"
          aria-busy="true"
        >
          <h1>{@route_spec.page_display_label}</h1>
          <p>Loading this view</p>
        </section>

        <section
          :if={
            @route_spec.route_id not in [
              :app,
              :settings,
              :formation,
              :stake,
              :redeem,
              :techtree,
              :techtree_tree,
              :techtree_node,
              :autolaunch,
              :autolaunch_auctions,
              :autolaunch_auction,
              :autolaunch_tokens,
              :autolaunch_token,
              :autolaunch_launches,
              :autolaunch_launch,
              :autolaunch_subjects,
              :autolaunch_subject,
              :autolaunch_holdings,
              :autolaunch_create,
              :regent_profile
            ] &&
              @content_status == :error
          }
          class="shell-status"
          role="alert"
        >
          <h1>{@route_spec.page_display_label}</h1>
          <p>This view could not be loaded. Navigation remains available.</p>
        </section>

        <article :if={
          @route_spec.route_id not in [
            :app,
            :settings,
            :formation,
            :stake,
            :redeem,
            :techtree,
            :techtree_tree,
            :techtree_node,
            :autolaunch,
            :autolaunch_auctions,
            :autolaunch_auction,
            :autolaunch_tokens,
            :autolaunch_token,
            :autolaunch_launches,
            :autolaunch_launch,
            :autolaunch_subjects,
            :autolaunch_subject,
            :autolaunch_holdings,
            :autolaunch_create,
            :regent_profile
          ] &&
            @content_status == :ready
        }>
          <p>{@content.eyebrow}</p>
          <p><span aria-label="Capability status">{@content.status}</span></p>
          <h1>{@content.title}</h1>
          <p>{@content.summary}</p>
          <dl :if={@content.details != []}>
            <div :for={{label, value} <- @content.details}>
              <dt>{label}</dt>
              <dd>{value}</dd>
            </div>
          </dl>
        </article>
      </:content>
    </.shell>
    """
  end

  defp content_failed(socket, reason) do
    assign(socket,
      content: nil,
      content_error: inspect(reason),
      content_status: :error,
      content_async_name: nil
    )
  end

  defp cancel_content(%{assigns: %{content_async_name: nil}} = socket), do: socket

  defp cancel_content(%{assigns: %{content_async_name: name}} = socket) do
    cancel_async(socket, name)
  end

  defp initial_presentation(%{local_state: %{presentation: %{default: presentation}}}),
    do: presentation

  defp initial_presentation(_route_spec), do: :none

  defp maybe_start_staking(socket, %{route_id: :app}, generation) do
    actor = staking_actor(socket)

    socket
    |> clear_staking_form()
    |> assign(staking: nil, staking_status: :loading)
    |> start_async({:staking, generation}, fn ->
      {generation, if(actor, do: Staking.account(actor: actor), else: Staking.overview())}
    end)
  end

  defp maybe_start_staking(socket, %{route_id: :stake}, generation),
    do: socket |> assign(staking: nil, staking_status: :loading) |> start_staking_read(generation)

  defp maybe_start_staking(socket, _route, _generation),
    do: socket |> clear_staking_form() |> assign(staking: nil, staking_status: :loading)

  defp clear_staking_form(socket),
    do:
      assign(socket,
        staking_action: "stake",
        staking_amount: "",
        staking_wallet: nil,
        staking_notice: nil
      )

  defp staking_read_failed(socket, :wrong_signer, generation),
    do:
      socket
      |> assign(
        staking_wallet: nil,
        staking_amount: "",
        staking_notice: %{
          tone: :error,
          message: "That wallet is not one of the wallets on your Regent account."
        }
      )
      |> start_staking_read(generation)

  defp staking_read_failed(socket, _, _), do: assign(socket, staking: nil, staking_status: :error)

  defp start_staking_read(socket, generation) do
    name = {:staking, generation}
    wallet = socket.assigns.staking_wallet
    opts = wallet_opts(socket)

    socket
    |> cancel_async(name)
    |> assign(staking_read: %{name: name})
    |> start_async(name, fn ->
      {generation,
       if(wallet, do: Staking.account_for_wallet(wallet, opts), else: Staking.overview())}
    end)
  end

  defp release_staking_read(%{assigns: %{staking_read: %{name: name}}} = socket, name),
    do: assign(socket, staking_read: nil)

  defp release_staking_read(socket, _), do: socket
  defp dismiss_settled_staking(socket, _), do: socket
  defp staking_reading?(%{staking_read: nil}), do: false
  defp staking_reading?(_), do: true

  defp current_account(%{principal: {:human, account}}), do: account
  defp current_account(_access_context), do: nil

  defp current_human_id(%{principal: {:human, account}}), do: account.id
  defp current_human_id(_access_context), do: nil

  defp load_verified_connections(socket, %{route_id: :settings}) do
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

  defp load_techtree_route(socket, %{route_id: :techtree}, _params) do
    case Techtree.list_trees() do
      {:ok, trees} ->
        assign(socket,
          techtree_trees: trees,
          techtree_tree: nil,
          techtree_nodes: [],
          techtree_edges: [],
          techtree_node: nil,
          techtree_provenance: nil,
          techtree_uplift_report: nil,
          techtree_payload_status: :not_available,
          techtree_notebook_artifact: nil,
          techtree_status: :ready
        )

      {:error, _error} ->
        assign(socket, techtree_trees: [], techtree_status: :error)
    end
  end

  defp load_techtree_route(socket, %{route_id: :techtree_tree}, %{"tree_slug" => slug}) do
    with {:ok, tree} when not is_nil(tree) <- Techtree.get_tree_by_slug(slug),
         {:ok, nodes} <- Techtree.list_tree_nodes(tree.id),
         {:ok, edges} <- Techtree.list_tree_edges(tree.id) do
      assign(socket,
        techtree_trees: list_techtree_roots(),
        techtree_tree: tree,
        techtree_nodes: Enum.map(nodes, &Provenance.browser_node/1),
        techtree_edges: edges,
        techtree_node: nil,
        techtree_provenance: nil,
        techtree_uplift_report: nil,
        techtree_payload_status: :not_available,
        techtree_notebook_artifact: nil,
        techtree_status: :ready
      )
    else
      {:ok, nil} ->
        assign(socket,
          techtree_tree: nil,
          techtree_nodes: [],
          techtree_edges: [],
          techtree_provenance: nil,
          techtree_uplift_report: nil,
          techtree_payload_status: :not_available,
          techtree_notebook_artifact: nil,
          techtree_status: :empty
        )

      {:error, _error} ->
        assign(socket,
          techtree_tree: nil,
          techtree_nodes: [],
          techtree_edges: [],
          techtree_provenance: nil,
          techtree_uplift_report: nil,
          techtree_payload_status: :not_available,
          techtree_notebook_artifact: nil,
          techtree_status: :error
        )
    end
  end

  defp load_techtree_route(socket, %{route_id: :techtree_node}, %{"node_id" => node_id}) do
    case Techtree.get_public_node(node_id) do
      {:ok, nil} ->
        assign(socket,
          techtree_node: nil,
          techtree_edges: [],
          techtree_provenance: nil,
          techtree_uplift_report: nil,
          techtree_payload_status: :not_available,
          techtree_notebook_artifact: nil,
          techtree_status: :empty
        )

      {:ok, node} ->
        {provenance, uplift_report, payload_status} = node_presentation(node)

        assign(socket,
          techtree_node: node,
          techtree_edges: [],
          techtree_provenance: provenance,
          techtree_uplift_report: uplift_report,
          techtree_payload_status: payload_status,
          techtree_notebook_artifact: current_notebook_artifact(node),
          techtree_status: :ready
        )

      {:error, _error} ->
        assign(socket,
          techtree_node: nil,
          techtree_edges: [],
          techtree_provenance: nil,
          techtree_uplift_report: nil,
          techtree_payload_status: :not_available,
          techtree_notebook_artifact: nil,
          techtree_status: :empty
        )
    end
  end

  defp load_techtree_route(socket, _route_spec, _params), do: socket

  defp node_presentation(node) do
    case Payload.fetch_if_referenced(node) do
      {:ok, %{bytes: bytes, verification: verification}} ->
        {Provenance.public_node(node, [], verification), project_uplift_report(node, bytes),
         :ready}

      {:error, :artifact_unavailable} ->
        verification = %{
          status: :unavailable,
          expected_hash: Map.get(node, :manifest_hash),
          actual_hash: nil
        }

        {Provenance.public_node(node, [], verification), nil, :artifact_unavailable}
    end
  end

  defp project_uplift_report(node, bytes) when is_binary(bytes) do
    if uplift_report_node?(node) do
      case UpliftReport.project_json(bytes) do
        {:ok, report} -> report
        :not_uplift_report -> UpliftReport.not_recognized()
      end
    else
      nil
    end
  end

  defp project_uplift_report(_node, _bytes), do: nil

  defp uplift_report_node?(node),
    do: Map.get(node, :kind) in [:uplift_report, "uplift_report"]

  defp current_notebook_artifact(%{payload_hash: payload_hash} = node)
       when is_binary(payload_hash) do
    case Techtree.list_current_notebook_artifacts(node.id, payload_hash) do
      {:ok, [artifact]} -> artifact
      _result -> nil
    end
  end

  defp current_notebook_artifact(_node), do: nil

  defp list_techtree_roots do
    case Techtree.list_trees() do
      {:ok, trees} -> trees
      {:error, _error} -> []
    end
  end

  defp load_autolaunch_route(socket, %{route_id: :autolaunch}, _params) do
    with {:ok, featured} <- Autolaunch.list_featured_auctions(),
         {:ok, recent} <- Autolaunch.list_recent_auctions(),
         {:ok, top} <- Autolaunch.list_top_tokens(),
         {:ok, graduated} <- Autolaunch.list_recently_graduated_tokens() do
      assign(socket,
        autolaunch_featured_auctions: featured,
        autolaunch_recent_auctions: recent,
        autolaunch_top_tokens: top,
        autolaunch_graduated_tokens: graduated,
        autolaunch_status: :ready
      )
    else
      {:error, _error} -> assign(socket, autolaunch_status: :error)
    end
  end

  defp load_autolaunch_route(socket, %{route_id: :autolaunch_auctions}, _params) do
    case Autolaunch.list_auctions() do
      {:ok, records} -> assign(socket, autolaunch_records: records, autolaunch_status: :ready)
      {:error, _error} -> assign(socket, autolaunch_records: [], autolaunch_status: :error)
    end
  end

  defp load_autolaunch_route(socket, %{route_id: :autolaunch_tokens}, _params) do
    case Autolaunch.list_tokens() do
      {:ok, records} -> assign(socket, autolaunch_records: records, autolaunch_status: :ready)
      {:error, _error} -> assign(socket, autolaunch_records: [], autolaunch_status: :error)
    end
  end

  defp load_autolaunch_route(socket, %{route_id: :autolaunch_launches}, _params) do
    case Autolaunch.list_launches() do
      {:ok, records} -> assign(socket, autolaunch_records: records, autolaunch_status: :ready)
      {:error, _error} -> assign(socket, autolaunch_records: [], autolaunch_status: :error)
    end
  end

  defp load_autolaunch_route(socket, %{route_id: :autolaunch_subjects}, _params) do
    case Autolaunch.list_subjects() do
      {:ok, records} -> assign(socket, autolaunch_records: records, autolaunch_status: :ready)
      {:error, _error} -> assign(socket, autolaunch_records: [], autolaunch_status: :error)
    end
  end

  defp load_autolaunch_route(
         socket,
         %{route_id: :autolaunch_auction},
         %{"auction_id" => id}
       ) do
    case Autolaunch.get_public_auction(id) do
      {:ok, nil} ->
        assign(socket, autolaunch_record: nil, autolaunch_status: :empty)

      {:ok, record} ->
        assign(socket, autolaunch_record: record, autolaunch_status: :ready)

      {:error, _error} ->
        assign(socket, autolaunch_record: nil, autolaunch_status: :empty)
    end
  end

  defp load_autolaunch_route(socket, %{route_id: :autolaunch_token}, %{"token_id" => id}) do
    case Autolaunch.get_public_token(id) do
      {:ok, nil} -> assign(socket, autolaunch_record: nil, autolaunch_status: :empty)
      {:ok, record} -> assign(socket, autolaunch_record: record, autolaunch_status: :ready)
      {:error, _error} -> assign(socket, autolaunch_record: nil, autolaunch_status: :empty)
    end
  end

  defp load_autolaunch_route(socket, %{route_id: :autolaunch_launch}, %{"id" => id}) do
    case Autolaunch.get_public_launch(id) do
      {:ok, nil} -> assign(socket, autolaunch_record: nil, autolaunch_status: :empty)
      {:ok, record} -> assign(socket, autolaunch_record: record, autolaunch_status: :ready)
      {:error, _error} -> assign(socket, autolaunch_record: nil, autolaunch_status: :error)
    end
  end

  defp load_autolaunch_route(socket, %{route_id: :autolaunch_subject}, %{"id" => id}) do
    case Autolaunch.get_public_subject(id) do
      {:ok, nil} ->
        assign(socket,
          autolaunch_record: nil,
          autolaunch_subject_tokens: [],
          autolaunch_subject_actions: [],
          autolaunch_subject_settlements: [],
          autolaunch_status: :empty
        )

      {:ok, subject} ->
        load_autolaunch_subject_details(socket, subject)

      {:error, _error} ->
        subject_load_error(socket)
    end
  end

  defp load_autolaunch_route(socket, %{route_id: :autolaunch_create}, _params) do
    case human_actor(socket) do
      %Human{} = actor ->
        case Autolaunch.list_my_launch_drafts(actor: actor) do
          {:ok, drafts} ->
            assign(socket,
              autolaunch_launch_drafts: drafts,
              autolaunch_status: :ready
            )

          {:error, _error} ->
            assign(socket,
              autolaunch_launch_drafts: [],
              autolaunch_status: :error
            )
        end

      nil ->
        assign(socket,
          autolaunch_launch_drafts: [],
          autolaunch_status: :ready
        )
    end
  end

  defp load_autolaunch_route(socket, %{route_id: :autolaunch_holdings}, _params) do
    with %Human{} = actor <- human_actor(socket),
         {:ok, positions} <- Autolaunch.list_my_bid_positions(actor: actor),
         {:ok, returnable} <- Autolaunch.list_my_returnable_bid_positions(actor: actor),
         {:ok, claimed} <- Autolaunch.list_my_claimed_token_positions(actor: actor) do
      assign(socket,
        autolaunch_bid_positions: positions,
        autolaunch_returnable_positions: returnable,
        autolaunch_claimed_token_positions: Enum.filter(claimed, & &1.token),
        autolaunch_status: :ready
      )
    else
      _error ->
        assign(socket,
          autolaunch_bid_positions: [],
          autolaunch_returnable_positions: [],
          autolaunch_claimed_token_positions: [],
          autolaunch_status: :error
        )
    end
  end

  defp load_autolaunch_route(socket, _route_spec, _params), do: socket

  defp load_autolaunch_subject_details(socket, subject) do
    with {:ok, tokens} <- Autolaunch.list_subject_tokens(subject.subject_id),
         {:ok, actions} <- Autolaunch.list_subject_actions(subject.subject_id),
         {:ok, settlements} <- Autolaunch.list_subject_settlements(subject.subject_id) do
      assign(socket,
        autolaunch_record: subject,
        autolaunch_subject_tokens: tokens,
        autolaunch_subject_actions: actions,
        autolaunch_subject_settlements: settlements,
        autolaunch_status: :ready
      )
    else
      {:error, _error} -> subject_load_error(socket)
    end
  end

  defp subject_load_error(socket) do
    assign(socket,
      autolaunch_record: nil,
      autolaunch_subject_tokens: [],
      autolaunch_subject_actions: [],
      autolaunch_subject_settlements: [],
      autolaunch_status: :error
    )
  end

  defp load_comments_route(socket, %{route_id: :techtree_node}) do
    set_comment_target(socket, :techtree_node, socket.assigns.techtree_node)
  end

  defp load_comments_route(socket, %{route_id: :autolaunch_auction}) do
    set_comment_target(socket, :autolaunch_auction, socket.assigns.autolaunch_record)
  end

  defp load_comments_route(socket, %{route_id: :autolaunch_token}) do
    set_comment_target(socket, :autolaunch_token, socket.assigns.autolaunch_record)
  end

  defp load_comments_route(socket, _route_spec), do: clear_comment_target(socket)

  defp set_comment_target(socket, _target_type, nil), do: clear_comment_target(socket)

  defp set_comment_target(socket, target_type, %{id: target_id}) do
    topic = Discussions.comment_topic(target_type, target_id)

    socket
    |> update_comment_subscription(topic)
    |> assign(
      comment_target: %{type: target_type, id: target_id},
      comment_request_id: Ash.UUID.generate(),
      comment_draft: "",
      comment_notice: nil
    )
    |> reload_comments()
  end

  defp clear_comment_target(socket) do
    socket
    |> update_comment_subscription(nil)
    |> assign(
      comments: [],
      comments_status: :ready,
      comment_reactions: %{},
      comment_target: nil,
      comment_request_id: Ash.UUID.generate(),
      comment_draft: "",
      comment_notice: nil
    )
  end

  defp update_comment_subscription(socket, next_topic) do
    current_topic = socket.assigns.comment_topic

    if connected?(socket) and current_topic != next_topic do
      if current_topic, do: Phoenix.PubSub.unsubscribe(AshPlatform.PubSub, current_topic)
      if next_topic, do: Phoenix.PubSub.subscribe(AshPlatform.PubSub, next_topic)
    end

    assign(socket, comment_topic: next_topic)
  end

  defp reload_comments(%{assigns: %{comment_target: %{type: type, id: id}}} = socket) do
    case Discussions.list_comments(type, id) do
      {:ok, comments} ->
        socket
        |> assign(comments: comments, comments_status: :ready)
        |> reload_comment_reactions()

      {:error, _error} ->
        assign(socket, comments: [], comments_status: :error, comment_reactions: %{})
    end
  end

  defp reload_comments(socket), do: socket

  defp reload_comment_reactions(
         %{assigns: %{comment_target: %{type: :techtree_node}, comments: comments}} = socket
       ) do
    comment_ids = Enum.map(comments, & &1.id)

    case Discussions.list_comment_reactions(comment_ids) do
      {:ok, reactions} ->
        assign(socket,
          comment_reactions:
            summarize_comment_reactions(
              reactions,
              current_human_id(socket.assigns.access_context)
            )
        )

      {:error, _error} ->
        assign(socket, comment_reactions: %{})
    end
  end

  defp reload_comment_reactions(socket), do: assign(socket, comment_reactions: %{})

  defp summarize_comment_reactions(reactions, current_human_id) do
    Enum.reduce(reactions, %{}, fn reaction, summaries ->
      summary =
        Map.get(summaries, reaction.comment_id, %{
          current: nil,
          counts: %{useful: 0, off_topic: 0, negative: 0}
        })

      summary =
        summary
        |> put_in([:counts, reaction.value], summary.counts[reaction.value] + 1)
        |> then(fn summary ->
          if reaction.reactor_id == current_human_id,
            do: %{summary | current: reaction.value},
            else: summary
        end)

      Map.put(summaries, reaction.comment_id, summary)
    end)
  end

  defp toggle_comment_reaction(comment, value, actor) do
    case Discussions.get_my_comment_reaction(comment.id, actor: actor) do
      {:ok, %{value: ^value} = reaction} ->
        case Discussions.remove_comment_reaction(reaction, actor: actor) do
          {:ok, _reaction} -> :ok
          :ok -> :ok
          {:error, error} -> {:error, error}
        end

      {:ok, nil} ->
        set_comment_reaction(comment.id, value, actor)

      {:ok, _reaction} ->
        set_comment_reaction(comment.id, value, actor)

      {:error, error} ->
        {:error, error}
    end
  end

  defp set_comment_reaction(comment_id, value, actor) do
    case Discussions.set_comment_reaction(comment_id, value, actor: actor) do
      {:ok, _reaction} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  defp reaction_value("useful"), do: {:ok, :useful}
  defp reaction_value("off_topic"), do: {:ok, :off_topic}
  defp reaction_value("negative"), do: {:ok, :negative}
  defp reaction_value(_value), do: {:error, :invalid_reaction}

  defp human_actor(%{assigns: %{access_context: %{principal: {:human, account}}}}),
    do: %Human{human_account_id: account.id}

  defp human_actor(_socket), do: nil

  defp maybe_start_redemption(socket, %{route_id: :redeem}, _), do: start_redemption_read(socket)

  defp maybe_start_redemption(socket, _, _) do
    socket
    |> cancel_redemption_read()
    |> cancel_open_sea_lookup()
    |> assign(
      redemption: nil,
      redemption_status: :loading,
      redemption_notice: nil,
      redemption_wallet: nil,
      owned_collectibles: %{status: :idle, animata: [], regents_club: []}
    )
  end

  defp start_redemption_read(socket) do
    socket = socket |> cancel_redemption_read() |> cancel_open_sea_lookup()
    generation = socket.assigns.redemption_generation + 1
    name = {:redemption, generation}
    wallet = socket.assigns.redemption_wallet
    collection = socket.assigns.redemption_collection
    token_id = parsed_token_id(socket.assigns.redemption_token_id)
    opts = wallet_opts(socket)

    socket
    |> assign(
      redemption: nil,
      redemption_status: :loading,
      redemption_generation: generation,
      redemption_read: %{name: name},
      owned_collectibles: %{
        status: if(wallet, do: :loading, else: :idle),
        animata: [],
        regents_club: []
      }
    )
    |> start_async(name, fn ->
      {generation,
       if(wallet,
         do: Redemption.account_for_wallet(wallet, collection, token_id, opts),
         else: Redemption.overview()
       )}
    end)
  end

  defp adopt_redemption_wallet(socket, wallet),
    do:
      socket
      |> assign(redemption_wallet: wallet, redemption_notice: nil)
      |> start_redemption_read()

  defp redemption_read_failed(socket, :wrong_signer),
    do:
      socket
      |> assign(
        redemption_wallet: nil,
        redemption_notice: %{
          tone: :error,
          message: "That wallet is not one of the wallets on your Regent account."
        }
      )
      |> start_redemption_read()

  defp redemption_read_failed(socket, _),
    do: assign(socket, redemption: nil, redemption_status: :error)

  defp cancel_redemption_read(%{assigns: %{redemption_read: nil}} = socket), do: socket

  defp cancel_redemption_read(socket),
    do:
      socket |> cancel_async(socket.assigns.redemption_read.name) |> assign(redemption_read: nil)

  defp release_redemption_read(%{assigns: %{redemption_read: %{name: name}}} = socket, name),
    do: assign(socket, redemption_read: nil)

  defp release_redemption_read(socket, _), do: socket
  defp dismiss_settled_redemption(socket, _), do: socket
  defp redemption_reading?(%{redemption_read: nil}), do: false
  defp redemption_reading?(_), do: true

  defp start_open_sea_lookup(
         %{assigns: %{redemption_wallet: wallet, route_spec: %{route_id: :redeem}}} = socket,
         generation
       )
       when is_binary(wallet) do
    name = {:open_sea, wallet, generation}
    opts = [actor: staking_actor(socket)]

    socket
    |> assign(
      open_sea_lookup: name,
      owned_collectibles: %{status: :loading, animata: [], regents_club: []}
    )
    |> start_async(name, fn -> OpenSea.fetch_owned_collectibles(wallet, opts) end)
  end

  defp start_open_sea_lookup(socket, _), do: socket
  defp cancel_open_sea_lookup(%{assigns: %{open_sea_lookup: nil}} = socket), do: socket

  defp cancel_open_sea_lookup(socket),
    do: socket |> cancel_async(socket.assigns.open_sea_lookup) |> assign(open_sea_lookup: nil)

  defp prepare_redemption(action, socket) do
    opts = wallet_opts(socket)
    wallet = socket.assigns.redemption_wallet
    collection = socket.assigns.redemption_collection
    token_id = parsed_token_id(socket.assigns.redemption_token_id)

    case action do
      "approve_nft_collection" when is_integer(token_id) ->
        Redemption.prepare_nft_approval(wallet, collection, token_id, opts)

      "approve_exact_usdc" when is_integer(token_id) ->
        Redemption.prepare_usdc_approval(wallet, collection, token_id, opts)

      "redeem" when is_integer(token_id) ->
        Redemption.prepare_redeem(wallet, collection, token_id, opts)

      "claim" ->
        Redemption.prepare_claim(wallet, opts)

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

  defp preparation_error(:operation_in_flight),
    do: "An earlier redemption action is still outstanding. Finish or withdraw it first."

  defp preparation_error(:nft_not_owned),
    do: "This wallet does not own the selected Animata token."

  defp preparation_error(:nft_approval_required), do: "Approve the selected NFT collection first."
  defp preparation_error(:insufficient_usdc), do: "This wallet needs at least 80 USDC."

  defp preparation_error(:exact_usdc_approval_required),
    do: "Set the USDC allowance to exactly 80 USDC before redeeming."

  defp preparation_error(:nothing_claimable), do: "No REGENT is unlocked to claim yet."

  defp preparation_error(:nft_owner_unavailable), do: unavailable_owner_copy()

  defp preparation_error(:chain_unavailable),
    do: "Base could not be reached to check this wallet. Nothing was prepared. Try again shortly."

  defp preparation_error(:wrong_signer),
    do:
      "This wallet is not one of the wallets on your account. Switch to a wallet you signed in with."

  defp preparation_error(:session_unavailable), do: "Your session changed. Reload and try again."

  defp preparation_error(_reason),
    do: "That action could not be prepared. Check the wallet and selection."

  defp staking_preparation_error(:operation_in_flight),
    do: "An earlier staking action is still outstanding. Finish or withdraw it first."

  defp staking_preparation_error(:no_claimable_usdc),
    do: "This wallet has no USDC rewards to claim right now."

  defp staking_preparation_error(:regent_rewards_not_funded),
    do: "The funded REGENT reward inventory is not enough to claim or reinvest yet."

  defp staking_preparation_error(:wrong_signer),
    do:
      "This wallet is not one of the wallets on your account. Switch to a wallet you signed in with."

  defp staking_preparation_error(:chain_unavailable),
    do: "Base could not be reached to check this wallet. Nothing was prepared. Try again shortly."

  defp staking_preparation_error(:session_unavailable),
    do: "Your session changed. Reload and try again."

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

  defp wallet_opts(socket),
    do: [actor: staking_actor(socket), context: %{session_lease: socket.assigns.session_lease}]

  defp authenticated?(%{principal: {:human, _}}), do: true
  defp authenticated?(_), do: false

  defp prepare_staking(action, amount, socket) do
    opts = wallet_opts(socket)
    wallet = socket.assigns.staking_wallet

    case action do
      "stake" -> Staking.prepare_stake(wallet, amount, opts)
      "unstake" -> Staking.prepare_unstake(wallet, amount, opts)
      "claim_usdc" -> Staking.prepare_claim_usdc(wallet, opts)
      "claim_regent" -> Staking.prepare_claim_regent(wallet, opts)
      "claim_and_restake_regent" -> Staking.prepare_claim_and_restake_regent(wallet, opts)
      _ -> {:error, :unknown_action}
    end
  end

  defp adopt_staking_wallet(socket, wallet),
    do:
      socket
      |> assign(
        staking: nil,
        staking_status: :loading,
        staking_wallet: wallet,
        staking_amount: "",
        staking_notice: nil
      )
      |> start_staking_read(socket.assigns.content_generation)

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
  defp limit_copy(reason), do: staking_preparation_error(reason)
  defp portioned(balance, "half"), do: div(balance, 2)
  defp portioned(balance, "max"), do: balance
end
