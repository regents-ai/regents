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
    RegentsClub,
    Staking
  }

  alias AshPlatform.Actors.Human
  alias AshPlatform.OpenSea.HoldingsCache
  alias AshPlatform.RegentsClub.Actions, as: RegentsClubActions
  alias AshPlatform.Staking.Facts, as: StakingFacts
  alias AshPlatform.Staking.SnapshotCache
  alias AshPlatform.WalletActions.Address
  alias AshPlatform.WalletActions.TransactionObserver
  alias AshPlatformWeb.AutolaunchLive
  alias AshPlatformWeb.FormationLive
  alias AshPlatformWeb.Plugs.LaunchGate
  alias AshPlatformWeb.RegentOpsLive
  alias AshPlatformWeb.RegentProfileLive
  alias AshPlatformWeb.RegentsClubMetadataLive
  alias AshPlatformWeb.RouteCatalog
  # Settings returns soon (founder, 2026-09-03): switched off, not removed.
  # alias AshPlatformWeb.SettingsLive

  @identity_providers %{"x" => :x, "github" => :github, "farcaster" => :farcaster}
  @staking_refresh_failure_notice "Refresh failed. The last confirmed Base snapshot remains on screen."
  # Names the budget it belongs to. The Redeem page has its own, unrelated
  # per-visitor limit on looking up owned NFTs, and the two refusals must never
  # read as the same thing.
  @shared_refresh_budget_notice "Contract data was refreshed for everyone moments ago. Ask for a new reading again in a few seconds."
  @redemption_preparation_failure_notice "That action could not be prepared. Check the wallet and selection."
  @regents_club_observation_interval 15_000
  @max_wallet_observations 8
  @open_sea_lookup_window 60_000
  @default_open_sea_lookups_per_minute 6

  @impl true
  def mount(params, session, socket) do
    route_spec = RouteCatalog.fetch!(socket.assigns.live_action, params)
    socket = assign(socket, :theme, session["theme"])

    case authorize_route(socket, route_spec) do
      {:redirect, socket} ->
        {:ok, socket}

      {:ok, socket} ->
        mount_authorized(params, route_spec, socket)
    end
  end

  defp mount_authorized(params, route_spec, socket) do
    if connected?(socket),
      do: Phoenix.PubSub.subscribe(AshPlatform.PubSub, SnapshotCache.topic())

    {:ok,
     assign(socket,
       content: nil,
       content_error: nil,
       content_async_name: nil,
       content_generation: 0,
       content_status: :loading,
       comments: [],
       comments_status: :ready,
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
       regents_club_metadata_status: :checking,
       regents_club_metadata_wallet: nil,
       regents_club_metadata_notice: nil,
       regents_club_metadata_attempts: %{},
       regents_club_metadata_review: nil,
       regents_club_metadata_result: nil,
       route_spec: route_spec,
       shell_instance: System.unique_integer([:positive, :monotonic]),
       wallet_observations: MapSet.new()
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
        route_spec: route_spec,
        route_params: params
      )

    socket =
      socket
      |> load_regent_route(route_spec, params)
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
         |> maybe_start_redemption(route_spec, generation)
         |> maybe_start_regents_club_metadata(route_spec, generation)}

      true ->
        {:noreply,
         socket
         |> assign(content_status: :ready)
         |> paint_initial_staking(route_spec)}
    end
  end

  defp authorize_route(socket, %{route_id: :regents_club_metadata}) do
    if RegentsClub.enabled?() and authenticated?(socket.assigns.access_context),
      do: {:ok, socket},
      else: {:redirect, redirect(socket, to: "/")}
  end

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
        {:regents_club_metadata_status, generation},
        {:ok, {generation, :ok, {:ok, %{state: :ready}}}},
        %{assigns: %{content_generation: generation}} = socket
      ) do
    {:noreply,
     assign(socket,
       regents_club_metadata_status: :ready,
       regents_club_metadata_notice: nil
     )}
  end

  def handle_async(
        {:regents_club_metadata_status, generation},
        {:ok, {generation, :ok, {:ok, %{state: :changed_unverified}}}},
        %{assigns: %{content_generation: generation}} = socket
      ) do
    {:noreply,
     assign(socket,
       regents_club_metadata_status: :unknown,
       regents_club_metadata_notice: metadata_notice(:changed_unverified)
     )}
  end

  def handle_async(
        {:regents_club_metadata_status, generation},
        _result,
        %{assigns: %{content_generation: generation}} = socket
      ) do
    {:noreply,
     assign(socket,
       regents_club_metadata_status: :unavailable,
       regents_club_metadata_notice: metadata_notice(:readiness_failed)
     )}
  end

  def handle_async({:regents_club_metadata_status, _generation}, _result, socket),
    do: {:noreply, socket}

  def handle_async(
        {:regents_club_metadata_observe, _attempt_id},
        {:ok, {:ok, {:finalized, result}}},
        socket
      ) do
    RegentsClub.disable!()

    {:noreply,
     assign(socket,
       regents_club_metadata_status: :closed,
       regents_club_metadata_attempts: %{},
       regents_club_metadata_review: nil,
       regents_club_metadata_result: result,
       regents_club_metadata_notice: metadata_notice(:finalized)
     )}
  end

  def handle_async(
        {:regents_club_metadata_observe, attempt_id},
        {:ok, {:ok, :pending}},
        socket
      ) do
    case socket.assigns.regents_club_metadata_attempts[attempt_id] do
      %{envelope: envelope} when is_map(envelope) ->
        if RegentsClubActions.observation_open?(envelope) do
          Process.send_after(
            self(),
            {:observe_regents_club_metadata, attempt_id},
            @regents_club_observation_interval
          )

          {:noreply, socket}
        else
          {:noreply, metadata_observation_unknown(socket, attempt_id)}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_async(
        {:regents_club_metadata_observe, attempt_id},
        {:ok, {:ok, :reverted}},
        socket
      ) do
    {:noreply,
     socket
     |> drop_metadata_attempt(attempt_id)
     |> assign(
       regents_club_metadata_status: :ready,
       regents_club_metadata_notice: metadata_notice(:reverted)
     )}
  end

  def handle_async(
        {:regents_club_metadata_observe, attempt_id},
        {:ok, {:ok, {:unknown, _reason}}},
        socket
      ) do
    {:noreply,
     socket
     |> drop_metadata_attempt(attempt_id)
     |> assign(
       regents_club_metadata_status: :unknown,
       regents_club_metadata_notice: metadata_notice(:unknown)
     )}
  end

  def handle_async({:regents_club_metadata_observe, attempt_id}, _result, socket) do
    {:noreply,
     socket
     |> drop_metadata_attempt(attempt_id)
     |> assign(
       regents_club_metadata_status: :unknown,
       regents_club_metadata_notice: metadata_notice(:unknown)
     )}
  end

  # A wallet reading answers for one account at its own block and says nothing
  # about the contract, so it is set beside the shared reading rather than over
  # it. With no shared reading on screen there is no dashboard to attach it to,
  # and the page keeps saying so.
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
             "select_owned_animata",
             "show_more_collectibles"
           ],
      do: handle_redemption_event(event, params, socket)

  def handle_event(
        "regents_club_metadata_active_wallet",
        %{"address" => address},
        %{assigns: %{route_spec: %{route_id: :regents_club_metadata}}} = socket
      ) do
    wallet = normalized_wallet(address)
    {:noreply, assign(socket, regents_club_metadata_wallet: wallet)}
  end

  def handle_event(
        "prepare_regents_club_metadata",
        %{"address" => address, "attempt_id" => attempt_id},
        %{
          assigns: %{
            route_spec: %{route_id: :regents_club_metadata},
            regents_club_metadata_status: status,
            regents_club_metadata_attempts: attempts
          }
        } = socket
      )
      when status in [:ready, :observing] do
    if Map.has_key?(attempts, attempt_id) do
      {:noreply, socket}
    else
      case RegentsClubActions.prepare(address, attempt_id, socket.assigns.session_lease) do
        {:ok, envelope} ->
          {:noreply,
           socket
           |> assign(
             regents_club_metadata_attempts:
               Map.put(attempts, attempt_id, %{envelope: envelope, handed_off: false}),
             regents_club_metadata_status: :review,
             regents_club_metadata_review: envelope,
             regents_club_metadata_notice: nil
           )}

        {:error, reason} ->
          {:noreply,
           socket
           |> assign(regents_club_metadata_notice: metadata_notice(reason))
           |> push_event("regents-club-metadata:refused", %{attempt_id: attempt_id})}
      end
    end
  end

  def handle_event("prepare_regents_club_metadata", _params, socket), do: {:noreply, socket}

  def handle_event(
        "confirm_regents_club_metadata",
        %{"attempt_id" => attempt_id},
        %{
          assigns: %{
            route_spec: %{route_id: :regents_club_metadata},
            regents_club_metadata_status: :review,
            regents_club_metadata_attempts: attempts
          }
        } = socket
      ) do
    case attempts[attempt_id] do
      %{handed_off: false} = attempt ->
        wallet = socket.assigns.regents_club_metadata_wallet

        if Address.equal?(wallet, attempt.envelope.expected_signer) do
          case RegentsClubActions.prepare(wallet, attempt_id, socket.assigns.session_lease) do
            {:ok, fresh_envelope} ->
              fresh_attempt =
                attempt
                |> Map.put(:envelope, fresh_envelope)
                |> Map.put(:handed_off, true)

              {:noreply,
               socket
               |> assign(
                 regents_club_metadata_attempts: Map.put(attempts, attempt_id, fresh_attempt),
                 regents_club_metadata_status: :observing,
                 regents_club_metadata_review: nil
               )
               |> push_event("regents-club-metadata:prepared", %{
                 attempt_id: attempt_id,
                 envelope: fresh_envelope
               })}

            {:error, reason} ->
              status = if RegentsClub.enabled?(), do: :ready, else: :unavailable

              {:noreply,
               socket
               |> drop_metadata_attempt(attempt_id)
               |> assign(
                 regents_club_metadata_status: status,
                 regents_club_metadata_review: nil,
                 regents_club_metadata_notice: metadata_notice(reason)
               )
               |> push_event("regents-club-metadata:refused", %{attempt_id: attempt_id})}
          end
        else
          {:noreply,
           socket
           |> drop_metadata_attempt(attempt_id)
           |> assign(
             regents_club_metadata_status: :ready,
             regents_club_metadata_review: nil,
             regents_club_metadata_notice: metadata_notice(:wallet_changed)
           )
           |> push_event("regents-club-metadata:refused", %{attempt_id: attempt_id})}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("confirm_regents_club_metadata", _params, socket), do: {:noreply, socket}

  def handle_event(
        "regents_club_metadata_submitted",
        %{"attempt_id" => attempt_id, "hash" => hash},
        socket
      ) do
    observe_metadata_attempt(
      socket,
      attempt_id,
      fn envelope ->
        RegentsClubActions.observe_hash(envelope, hash)
      end,
      %{hash: hash}
    )
  end

  def handle_event(
        "regents_club_metadata_submission_unknown",
        %{"attempt_id" => attempt_id},
        socket
      ) do
    observe_metadata_attempt(
      socket,
      attempt_id,
      &RegentsClubActions.recover_unknown/1,
      %{recovery: true}
    )
  end

  def handle_event(event, %{"attempt_id" => attempt_id}, socket)
      when event in ["regents_club_metadata_cancelled", "regents_club_metadata_refused"] do
    notice = if event == "regents_club_metadata_cancelled", do: :cancelled, else: :browser_refused

    {:noreply,
     socket
     |> drop_metadata_attempt(attempt_id)
     |> assign(
       regents_club_metadata_status: :ready,
       regents_club_metadata_notice: metadata_notice(notice)
     )}
  end

  def handle_event("regents_club_metadata_browser_refused", _params, socket) do
    {:noreply, assign(socket, regents_club_metadata_notice: metadata_notice(:browser_refused))}
  end

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

  # Only the pages that asked for the reading hear that it failed, and what they
  # were already showing stays on screen.
  def handle_info({:staking_snapshot_unavailable, _reason}, socket) do
    {:noreply,
     socket
     |> assign(staking_shared_reading: false)
     |> shared_read_failed()}
  end

  def handle_info(
        {:comments_changed, target_type, target_id},
        %{assigns: %{comment_target: %{type: target_type, id: target_id}}} = socket
      ) do
    notice = socket.assigns.comment_notice || %{tone: :info, message: "Comments updated."}
    {:noreply, socket |> assign(comment_notice: notice) |> reload_comments()}
  end

  def handle_info({:comments_changed, _target_type, _target_id}, socket), do: {:noreply, socket}

  def handle_info({:observe_regents_club_metadata, attempt_id}, socket) do
    case socket.assigns.regents_club_metadata_attempts[attempt_id] do
      %{envelope: envelope} = attempt ->
        if RegentsClubActions.observation_open?(envelope) do
          {:noreply,
           start_async(socket, {:regents_club_metadata_observe, attempt_id}, fn ->
             if attempt[:recovery],
               do: RegentsClubActions.recover_unknown(envelope),
               else: RegentsClubActions.observe_hash(envelope, attempt[:hash])
           end)}
        else
          {:noreply, metadata_observation_unknown(socket, attempt_id)}
        end

      nil ->
        {:noreply, socket}
    end
  end

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
      content_status={@content_status}
      shell_instance={@shell_instance}
      theme={@theme}
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

        <%!-- Settings returns soon (founder, 2026-09-03): switched off, not removed.
        <SettingsLive.page
          :if={@route_spec.route_id == :settings}
          verified_connections={@verified_connections}
          verified_connections_notice={@verified_connections_notice}
        />
        --%>

        <RegentsClubMetadataLive.page
          :if={@route_spec.route_id == :regents_club_metadata}
          status={@regents_club_metadata_status}
          wallet={@regents_club_metadata_wallet}
          notice={@regents_club_metadata_notice}
          result={@regents_club_metadata_result}
          review={@regents_club_metadata_review}
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

        <.wallet_reconnect_dialog :if={@wallet_reconnect} request={@wallet_reconnect} />

        <section
          :if={
            @route_spec.route_id not in [
              :app,
              :settings,
              :formation,
              :stake,
              :redeem,
              :regents_club_metadata,
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
          <AshPlatformWeb.Components.Loading.panel
            id="shell-content-skeleton"
            label={@route_spec.page_display_label}
          />
        </section>

        <section
          :if={
            @route_spec.route_id not in [
              :app,
              :settings,
              :formation,
              :stake,
              :redeem,
              :regents_club_metadata,
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
            :regents_club_metadata,
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

  defp maybe_start_regents_club_metadata(
         socket,
         %{route_id: :regents_club_metadata},
         generation
       ) do
    lease = socket.assigns.session_lease

    socket
    |> assign(regents_club_metadata_status: :checking)
    |> start_async({:regents_club_metadata_status, generation}, fn ->
      {generation, RegentsClubActions.deployment_readiness(lease), RegentsClubActions.status()}
    end)
  end

  defp maybe_start_regents_club_metadata(socket, _route_spec, _generation), do: socket

  defp observe_metadata_attempt(socket, attempt_id, observer, extra) do
    case socket.assigns.regents_club_metadata_attempts[attempt_id] do
      %{envelope: envelope, handed_off: true} = attempt ->
        if RegentsClubActions.observation_open?(envelope) do
          attempts =
            Map.put(
              socket.assigns.regents_club_metadata_attempts,
              attempt_id,
              Map.merge(attempt, extra)
            )

          {:noreply,
           socket
           |> assign(
             regents_club_metadata_attempts: attempts,
             regents_club_metadata_status: :observing,
             regents_club_metadata_notice: nil
           )
           |> start_async({:regents_club_metadata_observe, attempt_id}, fn ->
             observer.(envelope)
           end)}
        else
          {:noreply, metadata_observation_unknown(socket, attempt_id)}
        end

      nil ->
        {:noreply, socket}

      _not_handed_off ->
        {:noreply, socket}
    end
  end

  defp metadata_observation_unknown(socket, attempt_id) do
    socket
    |> drop_metadata_attempt(attempt_id)
    |> assign(
      regents_club_metadata_status: :unknown,
      regents_club_metadata_notice: metadata_notice(:unknown)
    )
  end

  defp drop_metadata_attempt(socket, attempt_id) do
    assign(
      socket,
      regents_club_metadata_attempts:
        Map.delete(socket.assigns.regents_club_metadata_attempts, attempt_id)
    )
  end

  defp metadata_notice(:finalized),
    do: %{tone: :success, message: "The exact cutover finalized and this route is now closed."}

  defp metadata_notice(:reverted),
    do: %{
      tone: :error,
      message: "The selected wallet transaction reverted onchain. No metadata change finalized."
    }

  defp metadata_notice(:cancelled),
    do: %{tone: :info, message: "The wallet request was canceled. It will not be retried."}

  defp metadata_notice(:unknown),
    do: %{
      tone: :error,
      message: "The submission outcome is unknown. Manual founder review is required."
    }

  defp metadata_notice(:browser_refused),
    do: %{
      tone: :error,
      message: "Keep one selected Ethereum wallet on Base through confirmation. Nothing was sent."
    }

  defp metadata_notice(:wallet_changed),
    do: %{
      tone: :error,
      message: "The selected Privy wallet changed after review. Review again. Nothing was sent."
    }

  defp metadata_notice(:session_unavailable),
    do: %{tone: :error, message: "The verified session changed. Reload before continuing."}

  defp metadata_notice(:readiness_failed),
    do: %{tone: :error, message: "Privy or trusted Base RPC readiness did not pass."}

  defp metadata_notice(:changed_unverified),
    do: %{
      tone: :error,
      message:
        "The URI changed, but this node has no exact finalized transaction evidence. Manual founder review is required."
    }

  defp metadata_notice(_reason),
    do: %{tone: :error, message: "The exact cutover could not be prepared. Nothing was sent."}

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
          "Please reconnect to the active wallet '#{short_wallet(account_wallet)}' to interact onchain."}

  defp wallet_gate(_account_wallet, _active_wallet), do: :ready

  defp gate_state({:mismatch, _request}), do: :mismatch
  defp gate_state(gate), do: gate

  defp reconnect_request({:mismatch, request}), do: request
  defp reconnect_request(_gate), do: nil

  defp account_wallet(account), do: normalized_wallet(Map.get(account, :wallet_address))

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
        assign(socket, comments: comments, comments_status: :ready)

      {:error, _error} ->
        assign(socket, comments: [], comments_status: :error)
    end
  end

  defp reload_comments(socket), do: socket

  defp human_actor(%{assigns: %{access_context: %{principal: {:human, account}}}}),
    do: %Human{human_account_id: account.id}

  defp human_actor(_socket), do: nil

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
