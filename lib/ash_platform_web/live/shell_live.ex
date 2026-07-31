defmodule AshPlatformWeb.ShellLive do
  use AshPlatformWeb, :live_view

  import AshPlatformWeb.Components.Shell
  import AshPlatformWeb.RedeemLive
  import AshPlatformWeb.StakeLive

  alias AshPlatform.{
    Autolaunch,
    ContentCoordinator,
    Discussions,
    Formation,
    Redemption,
    Staking,
    Techtree
  }

  alias AshPlatform.Actors.Human
  alias AshPlatform.WalletActions.Envelope
  alias AshPlatformWeb.AutolaunchLive
  alias AshPlatformWeb.FormationLive
  alias AshPlatformWeb.RegentOpsLive
  alias AshPlatformWeb.RegentProfileLive
  alias AshPlatformWeb.RouteCatalog
  alias AshPlatformWeb.SettingsLive
  alias AshPlatformWeb.TechtreeLive

  @autolaunch_wallet_open_minimum_seconds 60

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
       app_targets: RouteCatalog.app_targets(),
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
       autolaunch_buyback_fields: %{"amount_usdc" => "", "minimum_regent_output" => ""},
       autolaunch_buyback_notice: nil,
       autolaunch_buyback_prepared: nil,
       autolaunch_buyback_submission: nil,
       autolaunch_buyback_confirmation_name: nil,
       autolaunch_buyback_expiry_ref: nil,
       autolaunch_buyback_signing?: false,
       autolaunch_bid_positions: [],
       autolaunch_returnable_positions: [],
       autolaunch_claimed_token_positions: [],
       autolaunch_bid_fields: %{"amount" => "", "max_price" => ""},
       autolaunch_bid_quote: nil,
       autolaunch_bid_notice: nil,
       autolaunch_bid_prepared: nil,
       autolaunch_bid_submission: nil,
       autolaunch_bid_confirmation_name: nil,
       autolaunch_bid_expiry_ref: nil,
       autolaunch_bid_signing?: false,
       autolaunch_launch_drafts: [],
       autolaunch_draft_fields: %{
         "title" => "",
         "token_name" => "",
         "symbol" => "",
         "summary" => ""
       },
       autolaunch_draft_notice: nil,
       autolaunch_status: :loading,
       techtree_trees: [],
       techtree_tree: nil,
       techtree_nodes: [],
       techtree_edges: [],
       techtree_node: nil,
       techtree_notebook_artifact: nil,
       techtree_status: :loading,
       regent: socket.assigns.current_regent,
       regent_notice: nil,
       regent_status: if(socket.assigns.current_regent, do: :ready, else: :empty),
       formation_fields: %{"display_name" => "", "slug" => ""},
       cloud_runtime: nil,
       cloud_status: :empty,
       cloud_notice: nil,
       presentation: initial_presentation(route_spec),
       formation_panel: initial_formation_panel(route_spec),
       redemption: nil,
       redemption_collection: "animata_i",
       redemption_token_id: "",
       redemption_notice: nil,
       redemption_prepared: nil,
       redemption_submission: nil,
       redemption_confirmation_name: nil,
       redemption_async_name: nil,
       redemption_expiry_ref: nil,
       redemption_generation: 0,
       redemption_signing?: false,
       redemption_status: :loading,
       staking: nil,
       staking_amount: "",
       staking_notice: nil,
       staking_prepared: nil,
       staking_submission: nil,
       staking_confirmation_name: nil,
       staking_expiry_ref: nil,
       staking_signing?: false,
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
        formation_panel: initial_formation_panel(route_spec),
        route_spec: route_spec,
        route_params: params
      )

    socket =
      socket
      |> load_regent_route(route_spec, params)
      |> load_techtree_route(route_spec, params)
      |> load_autolaunch_route(route_spec, params)
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
        {:staking, generation},
        {:ok, {generation, {:ok, staking}}},
        %{assigns: %{content_generation: generation}} = socket
      ) do
    {:noreply, assign(socket, staking: staking, staking_status: :ready)}
  end

  def handle_async(
        {:staking, generation},
        {:ok, {generation, {:error, _reason}}},
        %{assigns: %{content_generation: generation}} = socket
      ) do
    {:noreply, assign(socket, staking: nil, staking_status: :error)}
  end

  def handle_async({:staking, _generation}, _result, socket), do: {:noreply, socket}

  def handle_async(
        {:redemption, generation},
        {:ok, {generation, {:ok, redemption}}},
        %{
          assigns: %{
            route_spec: %{route_id: :redeem},
            redemption_generation: generation
          }
        } = socket
      ) do
    {:noreply,
     assign(socket,
       redemption: redemption,
       redemption_status: :ready,
       redemption_async_name: nil
     )}
  end

  def handle_async(
        {:redemption, generation},
        {:ok, {generation, {:error, _reason}}},
        %{
          assigns: %{
            route_spec: %{route_id: :redeem},
            redemption_generation: generation
          }
        } = socket
      ) do
    {:noreply,
     assign(socket, redemption: nil, redemption_status: :error, redemption_async_name: nil)}
  end

  def handle_async({:redemption, _generation}, _result, socket), do: {:noreply, socket}

  def handle_async(
        {:redemption_confirmation, action_id},
        {:ok, {:ok, %{receipt_verified: true, transaction_reverted: true}}},
        %{
          assigns: %{
            route_spec: %{route_id: :redeem},
            redemption_prepared: %{action_id: action_id},
            redemption_confirmation_name: {:redemption_confirmation, action_id}
          }
        } = socket
      ) do
    {:noreply,
     socket
     |> cancel_redemption_expiry()
     |> assign(
       redemption_prepared: nil,
       redemption_submission: nil,
       redemption_confirmation_name: nil,
       redemption_signing?: false,
       redemption_notice: %{
         tone: :error,
         message: "The redemption transaction reverted. Prepare a new action when ready."
       }
     )
     |> push_event("redemption:reverted", %{})}
  end

  def handle_async(
        {:redemption_confirmation, action_id},
        {:ok, {:ok, %{receipt_verified: true} = result}},
        %{
          assigns: %{
            route_spec: %{route_id: :redeem},
            redemption_prepared: %{action_id: action_id},
            redemption_confirmation_name: {:redemption_confirmation, action_id}
          }
        } = socket
      ) do
    refresh_delayed? = not is_nil(result[:refresh_error])

    notice =
      if refresh_delayed? do
        %{
          tone: :success,
          message:
            "Confirmed on Base. Redemption details could not refresh yet; try again shortly."
        }
      else
        %{tone: :success, message: "Confirmed on Base. Your redemption details are current."}
      end

    {:noreply,
     socket
     |> cancel_redemption_expiry()
     |> assign(
       redemption: result[:redemption] || socket.assigns.redemption,
       redemption_status: :ready,
       redemption_prepared: nil,
       redemption_submission:
         Map.merge(socket.assigns.redemption_submission || %{}, %{status: :confirmed}),
       redemption_confirmation_name: nil,
       redemption_signing?: false,
       redemption_notice: notice
     )
     |> push_event("redemption:confirmed", %{})}
  end

  def handle_async(
        {:redemption_confirmation, action_id},
        result,
        %{
          assigns: %{
            route_spec: %{route_id: :redeem},
            redemption_confirmation_name: {:redemption_confirmation, action_id}
          }
        } = socket
      )
      when elem(result, 0) in [:ok, :exit] do
    {:noreply,
     assign(socket,
       redemption_confirmation_name: nil,
       redemption_signing?: false,
       redemption_notice: %{
         tone: :info,
         message: "The transaction is not confirmed yet. Retry verification shortly."
       }
     )}
  end

  def handle_async({:redemption_confirmation, _action_id}, _result, socket),
    do: {:noreply, socket}

  def handle_async(
        {:staking_confirmation, action_id},
        {:ok, {:ok, %{staking: staking}}},
        %{
          assigns: %{
            route_spec: %{route_id: :stake},
            staking_prepared: %{action_id: action_id},
            staking_confirmation_name: {:staking_confirmation, action_id}
          }
        } = socket
      )
      when not is_nil(staking) do
    {:noreply,
     socket
     |> assign(
       staking: staking,
       staking_status: :ready,
       staking_prepared: nil,
       staking_submission:
         Map.merge(socket.assigns.staking_submission || %{}, %{status: :confirmed}),
       staking_confirmation_name: nil,
       staking_signing?: false,
       staking_notice: %{
         tone: :success,
         message: "Confirmed on Base. Your staking details are current."
       }
     )
     |> push_event("staking:confirmed", %{})}
  end

  def handle_async(
        {:staking_confirmation, action_id},
        {:ok, {:ok, %{receipt_verified: true, transaction_reverted: true}}},
        %{
          assigns: %{
            route_spec: %{route_id: :stake},
            staking_prepared: %{action_id: action_id},
            staking_confirmation_name: {:staking_confirmation, action_id}
          }
        } = socket
      ) do
    {:noreply,
     socket
     |> assign(
       staking_prepared: nil,
       staking_submission: nil,
       staking_confirmation_name: nil,
       staking_signing?: false,
       staking_notice: %{
         tone: :error,
         message: "The staking transaction reverted. Prepare a new action when ready."
       }
     )
     |> push_event("staking:action-reverted", %{})}
  end

  def handle_async(
        {:staking_confirmation, action_id},
        {:ok, {:ok, %{receipt_verified: true, staking: nil}}},
        %{
          assigns: %{
            route_spec: %{route_id: :stake},
            staking_prepared: %{action_id: action_id},
            staking_confirmation_name: {:staking_confirmation, action_id}
          }
        } = socket
      ) do
    {:noreply,
     socket
     |> assign(
       staking_prepared: nil,
       staking_submission:
         Map.merge(socket.assigns.staking_submission || %{}, %{status: :confirmed}),
       staking_confirmation_name: nil,
       staking_signing?: false,
       staking_notice: %{
         tone: :success,
         message: "Confirmed on Base. Staking details could not refresh yet."
       }
     )
     |> push_event("staking:confirmed", %{})}
  end

  def handle_async(
        {:staking_confirmation, action_id},
        {:ok, {:error, _reason}},
        %{
          assigns: %{
            route_spec: %{route_id: :stake},
            staking_confirmation_name: {:staking_confirmation, action_id}
          }
        } = socket
      ) do
    {:noreply,
     assign(socket,
       staking_confirmation_name: nil,
       staking_signing?: false,
       staking_notice: %{tone: :error, message: "The transaction could not be confirmed on Base."}
     )}
  end

  def handle_async(
        {:staking_confirmation, action_id},
        {:exit, _reason},
        %{
          assigns: %{
            route_spec: %{route_id: :stake},
            staking_confirmation_name: {:staking_confirmation, action_id}
          }
        } = socket
      ) do
    {:noreply,
     assign(socket,
       staking_confirmation_name: nil,
       staking_signing?: false,
       staking_notice: %{tone: :error, message: "The transaction could not be confirmed on Base."}
     )}
  end

  def handle_async({:staking_confirmation, _action_id}, _result, socket), do: {:noreply, socket}

  def handle_async(
        {:staking_approval_status, action_id},
        {:ok, {:ok, :reverted}},
        %{assigns: %{staking_prepared: %{action_id: action_id}}} = socket
      ) do
    {:noreply,
     socket
     |> assign(
       staking_prepared: nil,
       staking_submission: nil,
       staking_signing?: false,
       staking_notice: %{
         tone: :error,
         message: "The REGENT approval was reverted. Prepare the stake again when ready."
       }
     )
     |> push_event("staking:approval-reverted", %{})}
  end

  def handle_async(
        {:staking_approval_status, action_id},
        {:ok, {:ok, :success}},
        %{assigns: %{staking_prepared: %{action_id: action_id}}} = socket
      ) do
    {:noreply,
     assign(socket,
       staking_signing?: false,
       staking_submission:
         Map.put(socket.assigns.staking_submission, :status, :approval_verified),
       staking_notice: %{tone: :info, message: "REGENT approval confirmed. Continue to staking."}
     )}
  end

  def handle_async({:staking_approval_status, _action_id}, _result, socket),
    do:
      {:noreply,
       assign(socket,
         staking_signing?: false,
         staking_notice: %{
           tone: :info,
           message: "The REGENT approval is not confirmed yet. Retry verification shortly."
         }
       )}

  def handle_async(
        {:autolaunch_bid_approval_status, action_id},
        {:ok, {:ok, :reverted}},
        %{assigns: %{autolaunch_bid_prepared: %{action_id: action_id}}} = socket
      ) do
    {:noreply,
     socket
     |> cancel_autolaunch_bid_expiry()
     |> assign(
       autolaunch_bid_prepared: nil,
       autolaunch_bid_submission: nil,
       autolaunch_bid_signing?: false,
       autolaunch_bid_notice: %{
         tone: :error,
         message: "The quote-token approval reverted. Prepare the bid again when ready."
       }
     )
     |> push_event("autolaunch-bid:approval-reverted", %{})}
  end

  def handle_async(
        {:autolaunch_bid_approval_status, action_id},
        {:ok, {:ok, :success}},
        %{assigns: %{autolaunch_bid_prepared: %{action_id: action_id}}} = socket
      ) do
    {:noreply,
     assign(socket,
       autolaunch_bid_signing?: false,
       autolaunch_bid_submission:
         Map.put(socket.assigns.autolaunch_bid_submission, :status, :approval_verified),
       autolaunch_bid_notice: %{
         tone: :info,
         message: "Quote-token approval confirmed. Continue to the bid."
       }
     )}
  end

  def handle_async(
        {:autolaunch_bid_approval_status, action_id},
        _result,
        %{assigns: %{autolaunch_bid_prepared: %{action_id: action_id}}} = socket
      ) do
    {:noreply,
     assign(socket,
       autolaunch_bid_signing?: false,
       autolaunch_bid_notice: %{
         tone: :info,
         message: "The quote-token approval is not confirmed yet. Retry verification shortly."
       }
     )}
  end

  def handle_async({:autolaunch_bid_approval_status, _action_id}, _result, socket),
    do: {:noreply, socket}

  def handle_async(
        {:autolaunch_buyback_confirmation, action_id},
        {:ok, {:ok, %{receipt_verified: true, transaction_reverted: true}}},
        %{assigns: %{autolaunch_buyback_prepared: %{action_id: action_id}}} = socket
      ) do
    {:noreply,
     socket
     |> cancel_autolaunch_buyback_expiry()
     |> assign(
       autolaunch_buyback_prepared: nil,
       autolaunch_buyback_submission: nil,
       autolaunch_buyback_confirmation_name: nil,
       autolaunch_buyback_signing?: false,
       autolaunch_buyback_notice: %{
         tone: :error,
         message: "The buyback transaction reverted. Prepare the settlement again when ready."
       }
     )
     |> push_event("autolaunch-buyback:reverted", %{})}
  end

  def handle_async(
        {:autolaunch_buyback_confirmation, action_id},
        {:ok, {:ok, %{receipt_verified: true, subject: subject}}},
        %{assigns: %{autolaunch_buyback_prepared: %{action_id: action_id}}} = socket
      ) do
    {:noreply,
     socket
     |> cancel_autolaunch_buyback_expiry()
     |> assign(
       autolaunch_record: subject,
       autolaunch_buyback_prepared: nil,
       autolaunch_buyback_submission:
         Map.merge(socket.assigns.autolaunch_buyback_submission || %{}, %{status: :confirmed}),
       autolaunch_buyback_confirmation_name: nil,
       autolaunch_buyback_signing?: false,
       autolaunch_buyback_notice: %{
         tone: :success,
         message: "Confirmed on Base. The stored subject record is current."
       }
     )
     |> push_event("autolaunch-buyback:confirmed", %{})}
  end

  def handle_async(
        {:autolaunch_buyback_confirmation, action_id},
        _result,
        %{
          assigns: %{
            autolaunch_buyback_confirmation_name: {:autolaunch_buyback_confirmation, action_id}
          }
        } = socket
      ) do
    {:noreply,
     assign(socket,
       autolaunch_buyback_confirmation_name: nil,
       autolaunch_buyback_signing?: false,
       autolaunch_buyback_notice: %{
         tone: :info,
         message: "The transaction is not confirmed yet. Retry verification shortly."
       }
     )}
  end

  def handle_async(
        {:autolaunch_bid_confirmation, action_id},
        {:ok, {:ok, %{receipt_verified: true, transaction_reverted: true}}},
        %{assigns: %{autolaunch_bid_prepared: %{action_id: action_id}}} = socket
      ) do
    {:noreply,
     socket
     |> cancel_autolaunch_bid_expiry()
     |> assign(
       autolaunch_bid_prepared: nil,
       autolaunch_bid_submission: nil,
       autolaunch_bid_confirmation_name: nil,
       autolaunch_bid_signing?: false,
       autolaunch_bid_notice: %{
         tone: :error,
         message: "The auction transaction reverted. Prepare the action again when ready."
       }
     )
     |> push_event("autolaunch-bid:reverted", %{})}
  end

  def handle_async(
        {:autolaunch_bid_confirmation, action_id},
        {:ok, {:ok, %{receipt_verified: true}}},
        %{assigns: %{autolaunch_bid_prepared: %{action_id: action_id}}} = socket
      ) do
    {:noreply,
     socket
     |> cancel_autolaunch_bid_expiry()
     |> assign(
       autolaunch_bid_prepared: nil,
       autolaunch_bid_submission:
         Map.merge(socket.assigns.autolaunch_bid_submission || %{}, %{status: :confirmed}),
       autolaunch_bid_confirmation_name: nil,
       autolaunch_bid_signing?: false,
       autolaunch_bid_notice: %{
         tone: :success,
         message: "Confirmed on Base. The stored auction records are current."
       }
     )
     |> push_event("autolaunch-bid:confirmed", %{})}
  end

  def handle_async(
        {:autolaunch_bid_confirmation, action_id},
        _result,
        %{assigns: %{autolaunch_bid_confirmation_name: {:autolaunch_bid_confirmation, action_id}}} =
          socket
      ) do
    {:noreply,
     assign(socket,
       autolaunch_bid_confirmation_name: nil,
       autolaunch_bid_signing?: false,
       autolaunch_bid_notice: %{
         tone: :info,
         message: "The transaction is not confirmed yet. Retry verification shortly."
       }
     )}
  end

  @impl true
  def handle_event(
        "form_regent",
        %{"regent" => %{"display_name" => display_name, "slug" => slug} = fields},
        socket
      ) do
    case Formation.form_regent(slug, display_name, actor: human_actor(socket)) do
      {:ok, regent} ->
        {:noreply, regent_saved(socket, regent, "#{regent.display_name} is ready.")}

      {:error, _error} ->
        {:noreply,
         assign(socket,
           formation_fields: fields,
           regent_notice: %{
             tone: :error,
             message: "That Regent could not be formed. Check the name and profile URL."
           }
         )}
    end
  end

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

  def handle_event("provision_cloud_runtime", _params, socket) do
    case Formation.provision_cloud_runtime(actor: human_actor(socket)) do
      {:ok, runtime} ->
        {:noreply,
         assign(socket,
           cloud_runtime: runtime,
           cloud_status: :ready,
           cloud_notice: %{
             tone: :success,
             message: "Sprite provisioned and verified."
           }
         )}

      {:error, _error} ->
        {:noreply,
         assign(socket,
           cloud_status: :error,
           cloud_notice: %{
             tone: :error,
             message:
               "The Sprite could not be provisioned. Check the provider setup and try again."
           }
         )}
    end
  end

  def handle_event(
        "refresh_cloud_runtime",
        _params,
        %{assigns: %{cloud_runtime: runtime}} = socket
      )
      when not is_nil(runtime) do
    case Formation.refresh_cloud_runtime(runtime, actor: human_actor(socket)) do
      {:ok, refreshed} ->
        {:noreply,
         assign(socket,
           cloud_runtime: refreshed,
           cloud_status: :ready,
           cloud_notice: %{tone: :success, message: "Sprite status refreshed."}
         )}

      {:error, _error} ->
        {:noreply,
         assign(socket,
           cloud_status: :error,
           cloud_notice: %{
             tone: :error,
             message: "The Sprite status could not be refreshed. Try again shortly."
           }
         )}
    end
  end

  def handle_event(
        "create_launch_draft",
        %{"launch_draft" => fields},
        socket
      ) do
    with %Human{} = actor <- human_actor(socket),
         {:ok, _draft} <-
           Autolaunch.create_launch_draft(
             fields["title"],
             fields["token_name"],
             fields["symbol"],
             empty_to_nil(fields["summary"]),
             actor: actor
           ),
         {:ok, drafts} <- Autolaunch.list_my_launch_drafts(actor: actor) do
      {:noreply,
       assign(socket,
         autolaunch_launch_drafts: drafts,
         autolaunch_draft_fields: %{
           "title" => "",
           "token_name" => "",
           "symbol" => "",
           "summary" => ""
         },
         autolaunch_draft_notice: %{
           tone: :success,
           message: "Draft saved. No auction or wallet action has started."
         }
       )}
    else
      _error ->
        {:noreply,
         assign(socket,
           autolaunch_draft_fields: fields,
           autolaunch_draft_notice: %{
             tone: :error,
             message: "That draft could not be saved. Check the launch and token details."
           }
         )}
    end
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
        "update_regent_profile",
        %{
          "profile" => %{
            "avatar_url" => avatar_url,
            "display_name" => display_name,
            "summary" => summary
          }
        },
        %{assigns: %{regent: regent}} = socket
      )
      when not is_nil(regent) do
    case Formation.update_profile(
           regent,
           display_name,
           empty_to_nil(summary),
           %{avatar_url: empty_to_nil(avatar_url)},
           actor: human_actor(socket)
         ) do
      {:ok, updated} ->
        {:noreply, regent_saved(socket, updated, "Public profile saved.")}

      {:error, _error} ->
        {:noreply,
         assign(socket,
           regent_notice: %{
             tone: :error,
             message:
               "The public profile could not be saved. Check the name, summary, and avatar URL."
           }
         )}
    end
  end

  def handle_event("staking_amount_changed", %{"amount" => amount}, socket) do
    if pending_submission?(socket.assigns.staking_submission) do
      {:noreply, socket}
    else
      {:noreply,
       assign(socket, staking_amount: amount, staking_prepared: nil, staking_notice: nil)}
    end
  end

  def handle_event("prepare_staking", params, socket) do
    action = params["action"]
    amount = params["amount"] || socket.assigns.staking_amount

    case {pending_submission?(socket.assigns.staking_submission),
          prepare_staking(action, amount, socket)} do
      {true, _result} ->
        {:noreply,
         assign(socket,
           staking_notice: %{
             tone: :info,
             message: "Verify the submitted transaction before preparing another action."
           }
         )}

      {false, {:ok, envelope}} ->
        if submitted_action?(socket.assigns.staking_submission, envelope.action_id) do
          {:noreply,
           assign(socket,
             staking_notice: %{
               tone: :error,
               message: "This action was already submitted. Verify its transaction instead."
             }
           )}
        else
          socket =
            socket
            |> assign(
              staking_prepared: envelope,
              staking_submission: nil,
              staking_signing?: false,
              staking_notice: %{
                tone: :info,
                message: "Review the details before opening your wallet."
              }
            )
            |> schedule_staking_expiry(envelope)

          {:noreply, socket}
        end

      {false, {:error, _reason}} ->
        {:noreply,
         assign(socket,
           staking_prepared: nil,
           staking_notice: %{
             tone: :error,
             message: "That action could not be prepared. Check the amount and wallet."
           }
         )}
    end
  end

  def handle_event("sign_prepared_staking", %{"action-id" => action_id}, socket) do
    submission = socket.assigns.staking_submission

    if socket.assigns.staking_signing? or main_submitted?(submission) do
      {:noreply, socket}
    else
      case socket.assigns.staking_prepared do
        %{action_id: ^action_id} = envelope ->
          if approval_authorized?(envelope, submission) do
            {:noreply,
             socket
             |> assign(
               staking_signing?: true,
               staking_notice: %{tone: :info, message: "Complete the request in your wallet."}
             )
             |> push_event("staking:prepared", %{
               envelope: envelope,
               approval_transaction_hash: submission && submission[:approval_transaction_hash]
             })}
          else
            {:noreply,
             assign(socket,
               staking_notice: %{
                 tone: :info,
                 message: "The REGENT approval must be verified before staking."
               }
             )}
          end

        _ ->
          {:noreply,
           assign(socket,
             staking_notice: %{
               tone: :error,
               message: "This review is no longer current. Prepare the action again."
             }
           )}
      end
    end
  end

  def handle_event(
        "staking_submitted",
        %{"action_id" => action_id, "phase" => phase, "transaction_hash" => hash},
        socket
      ) do
    case {socket.assigns.staking_prepared, valid_transaction_hash?(hash)} do
      {%{action_id: ^action_id}, true} ->
        submission = record_submission(socket.assigns.staking_submission, action_id, phase, hash)

        socket =
          assign(socket,
            staking_submission: submission,
            staking_signing?: false,
            staking_notice: %{tone: :info, message: submitted_copy(phase, hash)}
          )

        if phase == "approval" do
          {:noreply, start_approval_verification(socket, socket.assigns.staking_prepared, hash)}
        else
          {:noreply, socket}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("restore_staking_submission", params, socket) do
    envelope = params["envelope"] || params[:envelope]
    approval_hash = params["approval_transaction_hash"] || params[:approval_transaction_hash]
    transaction_hash = params["transaction_hash"] || params[:transaction_hash]
    actor = staking_actor(socket)

    with {:ok, restored} <- Staking.restore_submitted_action(envelope, actor: actor),
         true <- is_nil(approval_hash) or valid_transaction_hash?(approval_hash),
         true <- is_nil(transaction_hash) or valid_transaction_hash?(transaction_hash),
         true <- is_binary(approval_hash) or is_binary(transaction_hash) do
      status = if transaction_hash, do: :main_pending, else: :approval_pending

      socket =
        assign(socket,
          staking_prepared: restored,
          staking_submission: %{
            action_id: restored.action_id,
            approval_transaction_hash: approval_hash,
            transaction_hash: transaction_hash,
            status: status
          },
          staking_signing?: false,
          staking_notice: %{
            tone: :info,
            message: "A submitted transaction is waiting for verification."
          }
        )

      if is_binary(approval_hash) and is_nil(transaction_hash) and not Envelope.valid?(restored) do
        {:noreply, abandon_approval(socket, :expired)}
      else
        {:noreply, schedule_staking_expiry(socket, restored)}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event(
        "staking_approval_reverted",
        %{"action_id" => action_id, "transaction_hash" => hash},
        socket
      ) do
    with %{action_id: ^action_id} = envelope <- socket.assigns.staking_prepared,
         %{approval_transaction_hash: ^hash} <- socket.assigns.staking_submission do
      name = {:staking_approval_status, action_id}
      actor = staking_actor(socket)

      {:noreply,
       start_async(socket, name, fn ->
         Staking.verify_approval_submission(envelope, hash, actor: actor)
       end)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event(
        "confirm_staking",
        %{"action_id" => action_id, "transaction_hash" => transaction_hash},
        socket
      ) do
    case socket.assigns.staking_prepared do
      %{action_id: ^action_id} = envelope ->
        confirm_staking(socket, envelope, transaction_hash)

      _ ->
        {:noreply,
         assign(socket,
           staking_notice: %{
             tone: :error,
             message: "This wallet result does not match the reviewed action."
           }
         )}
    end
  end

  def handle_event("retry_staking_confirmation", _params, socket) do
    with %{action_id: action_id} = envelope <- socket.assigns.staking_prepared,
         %{action_id: ^action_id, transaction_hash: hash} when is_binary(hash) <-
           socket.assigns.staking_submission do
      confirm_staking(socket, envelope, hash)
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("retry_staking_approval_verification", _params, socket) do
    with %{action_id: action_id} = envelope <- socket.assigns.staking_prepared,
         %{action_id: ^action_id, approval_transaction_hash: hash} when is_binary(hash) <-
           socket.assigns.staking_submission do
      {:noreply, start_approval_verification(socket, envelope, hash)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("abandon_staking_approval", _params, socket) do
    case {socket.assigns.staking_prepared, socket.assigns.staking_submission} do
      {%{action_id: action_id},
       %{action_id: action_id, approval_transaction_hash: hash} = submission}
      when is_binary(hash) ->
        if is_nil(submission[:transaction_hash]),
          do: {:noreply, abandon_approval(socket, :user)},
          else: {:noreply, socket}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("refresh_staking", _params, socket) do
    generation = socket.assigns.content_generation
    {:noreply, maybe_start_staking(socket, socket.assigns.route_spec, generation)}
  end

  def handle_event("staking_wallet_failed", %{"message" => message}, socket) do
    message =
      if is_binary(message) and byte_size(message) <= 180,
        do: message,
        else: "The wallet action did not complete."

    notice =
      if socket.assigns.staking_submission do
        %{tone: :info, message: "Transaction submitted. Verification can be retried safely."}
      else
        %{tone: :error, message: message}
      end

    {:noreply, assign(socket, staking_signing?: false, staking_notice: notice)}
  end

  def handle_event("autolaunch_bid_changed", %{"bid" => fields}, socket) do
    quote =
      with auction when not is_nil(auction) <- socket.assigns.autolaunch_record,
           {:ok, quote} <-
             Autolaunch.quote_auction_bid(
               auction.id,
               fields["amount"],
               fields["max_price"]
             ) do
        quote
      else
        _ -> nil
      end

    {:noreply,
     assign(socket,
       autolaunch_bid_fields: fields,
       autolaunch_bid_quote: quote,
       autolaunch_bid_notice: nil,
       autolaunch_bid_prepared: nil
     )}
  end

  def handle_event("prepare_autolaunch_buyback", %{"buyback" => fields}, socket) do
    actor = human_actor(socket)
    wallet = expected_wallet(socket)

    result =
      case socket.assigns.autolaunch_record do
        subject when not is_nil(subject) ->
          Autolaunch.prepare_buyback_settlement(
            subject.subject_id,
            wallet,
            fields["amount_usdc"],
            fields["minimum_regent_output"],
            actor: actor
          )

        _ ->
          {:error, :subject_not_found}
      end

    prepare_autolaunch_buyback_review(socket, result, fields)
  end

  def handle_event(
        "sign_prepared_autolaunch_buyback",
        %{"action-id" => action_id},
        socket
      ) do
    case socket.assigns.autolaunch_buyback_prepared do
      %{action_id: ^action_id} = envelope ->
        if autolaunch_wallet_window_open?(envelope) and
             is_nil(socket.assigns.autolaunch_buyback_submission) and
             is_nil(socket.assigns.autolaunch_buyback_confirmation_name) do
          {:noreply,
           socket
           |> assign(
             autolaunch_buyback_signing?: true,
             autolaunch_buyback_notice: %{
               tone: :info,
               message: "Complete the reviewed request in your wallet."
             }
           )
           |> push_event("autolaunch-buyback:prepared", %{envelope: envelope})}
        else
          expired_autolaunch_buyback_review(socket)
        end

      _ ->
        {:noreply,
         assign(socket,
           autolaunch_buyback_notice: %{
             tone: :error,
             message: "This review is no longer current. Prepare the settlement again."
           }
         )}
    end
  end

  def handle_event(
        "autolaunch_buyback_submitted",
        %{"action_id" => action_id, "transaction_hash" => hash},
        socket
      ) do
    case {socket.assigns.autolaunch_buyback_prepared, valid_transaction_hash?(hash)} do
      {%{action_id: ^action_id}, true} ->
        {:noreply,
         socket
         |> cancel_autolaunch_buyback_expiry()
         |> assign(
           autolaunch_buyback_submission: %{
             action_id: action_id,
             transaction_hash: hash,
             status: :main_pending
           },
           autolaunch_buyback_signing?: false,
           autolaunch_buyback_notice: %{
             tone: :info,
             message: "Buyback transaction submitted: #{short_hash(hash)}"
           }
         )}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("restore_autolaunch_buyback_submission", params, socket) do
    envelope = params["envelope"] || params[:envelope]
    transaction_hash = params["transaction_hash"] || params[:transaction_hash]
    actor = human_actor(socket)

    with {:ok, restored} <-
           Autolaunch.restore_submitted_buyback_action(envelope, actor: actor),
         true <- valid_transaction_hash?(transaction_hash) do
      {:noreply,
       socket
       |> assign(
         autolaunch_buyback_prepared: restored,
         autolaunch_buyback_submission: %{
           action_id: restored.action_id,
           transaction_hash: transaction_hash,
           status: :main_pending
         },
         autolaunch_buyback_signing?: false,
         autolaunch_buyback_notice: %{
           tone: :info,
           message: "A submitted buyback transaction is waiting for verification."
         }
       )
       |> cancel_autolaunch_buyback_expiry()}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event(
        "confirm_autolaunch_buyback",
        %{"action_id" => action_id, "transaction_hash" => hash},
        socket
      ) do
    case socket.assigns.autolaunch_buyback_prepared do
      %{action_id: ^action_id} = envelope ->
        confirm_autolaunch_buyback(socket, envelope, hash)

      _ ->
        {:noreply,
         assign(socket,
           autolaunch_buyback_notice: %{
             tone: :error,
             message: "This wallet result does not match the reviewed settlement."
           }
         )}
    end
  end

  def handle_event("retry_autolaunch_buyback_confirmation", _params, socket) do
    with %{action_id: action_id} = envelope <- socket.assigns.autolaunch_buyback_prepared,
         %{action_id: ^action_id, transaction_hash: hash} when is_binary(hash) <-
           socket.assigns.autolaunch_buyback_submission do
      confirm_autolaunch_buyback(socket, envelope, hash)
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("cancel_autolaunch_buyback_review", _params, socket) do
    if is_nil(socket.assigns.autolaunch_buyback_submission) do
      {:noreply,
       socket
       |> cancel_autolaunch_buyback_expiry()
       |> assign(
         autolaunch_buyback_prepared: nil,
         autolaunch_buyback_signing?: false,
         autolaunch_buyback_notice: %{
           tone: :info,
           message: "The wallet review was cancelled."
         }
       )
       |> push_event("autolaunch-buyback:abandoned", %{})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("autolaunch_buyback_wallet_failed", %{"message" => message}, socket) do
    message =
      if is_binary(message) and byte_size(message) <= 180,
        do: message,
        else: "The wallet action did not complete."

    notice =
      if socket.assigns.autolaunch_buyback_submission do
        %{tone: :info, message: "Transaction submitted. Verification can be retried safely."}
      else
        %{tone: :error, message: message}
      end

    {:noreply,
     assign(socket,
       autolaunch_buyback_signing?: false,
       autolaunch_buyback_notice: notice
     )}
  end

  def handle_event("prepare_autolaunch_bid", %{"bid" => fields}, socket) do
    actor = human_actor(socket)
    wallet = expected_wallet(socket)

    result =
      case socket.assigns.autolaunch_record do
        auction when not is_nil(auction) ->
          Autolaunch.prepare_auction_bid(
            auction.id,
            wallet,
            fields["amount"],
            fields["max_price"],
            actor: actor
          )

        _ ->
          {:error, :auction_not_found}
      end

    prepare_autolaunch_review(socket, result, fields)
  end

  def handle_event(
        "prepare_autolaunch_bid_position",
        %{"action" => action, "bid-id" => bid_id},
        socket
      ) do
    actor = human_actor(socket)

    result =
      case action do
        "exit_bid" -> Autolaunch.prepare_bid_exit(bid_id, actor: actor)
        "return_quote_token" -> Autolaunch.prepare_bid_return(bid_id, actor: actor)
        "claim_bid" -> Autolaunch.prepare_bid_claim(bid_id, actor: actor)
        _ -> {:error, :invalid_action}
      end

    prepare_autolaunch_review(socket, result, socket.assigns.autolaunch_bid_fields)
  end

  def handle_event(
        "sign_prepared_autolaunch_bid",
        %{"action-id" => action_id},
        socket
      ) do
    case socket.assigns.autolaunch_bid_prepared do
      %{action_id: ^action_id} = envelope ->
        if autolaunch_wallet_window_open?(envelope) and
             autolaunch_approval_authorized?(
               envelope,
               socket.assigns.autolaunch_bid_submission
             ) and
             is_nil(socket.assigns.autolaunch_bid_confirmation_name) do
          {:noreply,
           socket
           |> assign(
             autolaunch_bid_signing?: true,
             autolaunch_bid_notice: %{
               tone: :info,
               message: "Complete the reviewed requests in your wallet."
             }
           )
           |> push_event("autolaunch-bid:prepared", %{envelope: envelope})}
        else
          expired_autolaunch_review(socket)
        end

      _ ->
        {:noreply,
         assign(socket,
           autolaunch_bid_notice: %{
             tone: :error,
             message: "This review is no longer current. Prepare the action again."
           }
         )}
    end
  end

  def handle_event(
        "autolaunch_bid_submitted",
        %{"action_id" => action_id, "phase" => phase, "transaction_hash" => hash},
        socket
      ) do
    case {socket.assigns.autolaunch_bid_prepared, valid_transaction_hash?(hash)} do
      {%{action_id: ^action_id}, true} ->
        submission =
          record_submission(socket.assigns.autolaunch_bid_submission, action_id, phase, hash)

        socket =
          socket
          |> cancel_autolaunch_bid_expiry()
          |> assign(
            autolaunch_bid_submission: submission,
            autolaunch_bid_signing?: false,
            autolaunch_bid_notice: %{
              tone: :info,
              message: autolaunch_submitted_copy(phase, hash)
            }
          )

        {:noreply, socket}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("restore_autolaunch_bid_submission", params, socket) do
    envelope = params["envelope"] || params[:envelope]
    approval_hash = params["approval_transaction_hash"] || params[:approval_transaction_hash]
    transaction_hash = params["transaction_hash"] || params[:transaction_hash]
    actor = human_actor(socket)

    with {:ok, restored} <- Autolaunch.restore_submitted_bid_action(envelope, actor: actor),
         true <- is_nil(approval_hash) or valid_transaction_hash?(approval_hash),
         true <- is_nil(transaction_hash) or valid_transaction_hash?(transaction_hash),
         true <- is_binary(approval_hash) or is_binary(transaction_hash) do
      status = if transaction_hash, do: :main_pending, else: :approval_pending

      {:noreply,
       socket
       |> assign(
         autolaunch_bid_prepared: restored,
         autolaunch_bid_submission: %{
           action_id: restored.action_id,
           approval_transaction_hash: approval_hash,
           transaction_hash: transaction_hash,
           status: status
         },
         autolaunch_bid_signing?: false,
         autolaunch_bid_notice: %{
           tone: :info,
           message: "A submitted auction transaction is waiting for verification."
         }
       )
       |> cancel_autolaunch_bid_expiry()}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("retry_autolaunch_bid_approval_verification", _params, socket) do
    with %{action_id: action_id} = envelope <- socket.assigns.autolaunch_bid_prepared,
         %{action_id: ^action_id, approval_transaction_hash: hash} when is_binary(hash) <-
           socket.assigns.autolaunch_bid_submission do
      {:noreply, start_autolaunch_approval_verification(socket, envelope, hash)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("cancel_autolaunch_bid_approval", _params, socket) do
    case {socket.assigns.autolaunch_bid_prepared, socket.assigns.autolaunch_bid_submission} do
      {%{action_id: action_id},
       %{action_id: action_id, approval_transaction_hash: hash} = submission}
      when is_binary(hash) ->
        if is_nil(submission[:transaction_hash]),
          do: {:noreply, cancel_autolaunch_approval(socket)},
          else: {:noreply, socket}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event(
        "confirm_autolaunch_bid",
        %{"action_id" => action_id, "transaction_hash" => hash} = params,
        socket
      ) do
    case socket.assigns.autolaunch_bid_prepared do
      %{action_id: ^action_id} = envelope ->
        confirm_autolaunch_bid(
          socket,
          envelope,
          hash,
          params["approval_transaction_hash"]
        )

      _ ->
        {:noreply,
         assign(socket,
           autolaunch_bid_notice: %{
             tone: :error,
             message: "This wallet result does not match the reviewed action."
           }
         )}
    end
  end

  def handle_event("retry_autolaunch_bid_confirmation", _params, socket) do
    with %{action_id: action_id} = envelope <- socket.assigns.autolaunch_bid_prepared,
         %{action_id: ^action_id, transaction_hash: hash} = submission
         when is_binary(hash) <- socket.assigns.autolaunch_bid_submission do
      confirm_autolaunch_bid(
        socket,
        envelope,
        hash,
        submission[:approval_transaction_hash]
      )
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("cancel_autolaunch_bid_review", _params, socket) do
    if is_nil(socket.assigns.autolaunch_bid_submission) do
      {:noreply,
       socket
       |> cancel_autolaunch_bid_expiry()
       |> assign(
         autolaunch_bid_prepared: nil,
         autolaunch_bid_signing?: false,
         autolaunch_bid_notice: %{tone: :info, message: "The wallet review was cancelled."}
       )
       |> push_event("autolaunch-bid:abandoned", %{})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("autolaunch_bid_wallet_failed", %{"message" => message}, socket) do
    message =
      if is_binary(message) and byte_size(message) <= 180,
        do: message,
        else: "The wallet action did not complete."

    {:noreply,
     assign(socket,
       autolaunch_bid_signing?: false,
       autolaunch_bid_notice: %{tone: :error, message: message}
     )}
  end

  def handle_event(event, params, socket)
      when event in [
             "redemption_selection_changed",
             "prepare_redemption",
             "sign_prepared_redemption",
             "redemption_submitted",
             "restore_redemption_submission",
             "confirm_redemption",
             "retry_redemption_confirmation",
             "cancel_redemption_review",
             "refresh_redemption",
             "redemption_wallet_failed"
           ],
      do: handle_redemption_event(event, params, socket)

  @impl true
  def handle_info({:staking_envelope_expired, action_id}, socket) do
    case {socket.assigns.staking_prepared, socket.assigns.staking_submission} do
      {%{action_id: ^action_id},
       %{action_id: ^action_id, approval_transaction_hash: hash} = submission}
      when is_binary(hash) ->
        if is_nil(submission[:transaction_hash]),
          do: {:noreply, abandon_approval(socket, :expired)},
          else: {:noreply, socket}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_info({:redemption_envelope_expired, action_id}, socket),
    do: handle_redemption_expiry(action_id, socket)

  def handle_info({:autolaunch_bid_envelope_expired, action_id}, socket) do
    case {socket.assigns.autolaunch_bid_prepared, socket.assigns.autolaunch_bid_submission} do
      {%{action_id: ^action_id}, submission} ->
        if autolaunch_submission_hash?(submission),
          do: {:noreply, socket},
          else: expired_autolaunch_review(socket)

      _ ->
        {:noreply, socket}
    end
  end

  def handle_info({:autolaunch_buyback_envelope_expired, action_id}, socket) do
    case {socket.assigns.autolaunch_buyback_prepared,
          socket.assigns.autolaunch_buyback_submission} do
      {%{action_id: ^action_id}, %{transaction_hash: hash}} when is_binary(hash) ->
        {:noreply, socket}

      {%{action_id: ^action_id}, _submission} ->
        expired_autolaunch_buyback_review(socket)

      _ ->
        {:noreply, socket}
    end
  end

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

  defp handle_redemption_event("redemption_selection_changed", params, socket) do
    if redemption_locked?(socket) do
      {:noreply, socket}
    else
      collection = params["collection"] || socket.assigns.redemption_collection
      token_id = params["token_id"] || ""

      socket =
        assign(socket,
          redemption_collection: collection,
          redemption_token_id: token_id,
          redemption_notice: nil
        )

      {:noreply, start_redemption_read(socket)}
    end
  end

  defp handle_redemption_event("prepare_redemption", %{"action" => action}, socket) do
    cond do
      redemption_locked?(socket) ->
        {:noreply,
         assign(socket,
           redemption_notice: %{
             tone: :info,
             message: "Finish or cancel the current review before preparing another action."
           }
         )}

      true ->
        case prepare_redemption(action, socket) do
          {:ok, envelope} ->
            {:noreply,
             socket
             |> assign(
               redemption_prepared: envelope,
               redemption_submission: nil,
               redemption_signing?: false,
               redemption_notice: %{
                 tone: :info,
                 message: "Review the details before opening your wallet."
               }
             )
             |> schedule_redemption_expiry(envelope)}

          {:error, reason} ->
            {:noreply,
             assign(socket,
               redemption_prepared: nil,
               redemption_notice: %{tone: :error, message: preparation_error(reason)}
             )}
        end
    end
  end

  defp handle_redemption_event("sign_prepared_redemption", %{"action-id" => action_id}, socket) do
    case {socket.assigns.redemption_prepared, socket.assigns.redemption_submission,
          socket.assigns.redemption_signing?} do
      {%{action_id: ^action_id} = envelope, nil, false} ->
        {:noreply,
         socket
         |> assign(
           redemption_signing?: true,
           redemption_notice: %{tone: :info, message: "Complete the request in your wallet."}
         )
         |> push_event("redemption:prepared", %{envelope: envelope})}

      _ ->
        {:noreply, socket}
    end
  end

  defp handle_redemption_event(
         "redemption_submitted",
         %{"action_id" => action_id, "transaction_hash" => hash},
         socket
       ) do
    case {socket.assigns.redemption_prepared, valid_transaction_hash?(hash)} do
      {%{action_id: ^action_id}, true} ->
        {:noreply,
         assign(socket,
           redemption_submission: %{
             action_id: action_id,
             transaction_hash: String.downcase(hash),
             status: :pending
           },
           redemption_signing?: false,
           redemption_notice: %{
             tone: :info,
             message: "Transaction submitted: #{short_hash(hash)}"
           }
         )}

      _ ->
        {:noreply, socket}
    end
  end

  defp handle_redemption_event("restore_redemption_submission", params, socket) do
    envelope = params["envelope"] || params[:envelope]
    hash = params["transaction_hash"] || params[:transaction_hash]
    actor = staking_actor(socket)

    with true <- valid_transaction_hash?(hash),
         {:ok, restored} <- Redemption.restore_submitted_action(envelope, actor: actor) do
      {:noreply,
       socket
       |> assign(
         redemption_prepared: restored,
         redemption_submission: %{
           action_id: restored.action_id,
           transaction_hash: String.downcase(hash),
           status: :pending
         },
         redemption_signing?: false,
         redemption_notice: %{
           tone: :info,
           message: "A submitted transaction is waiting for verification."
         }
       )
       |> schedule_redemption_expiry(restored)}
    else
      _ -> {:noreply, socket}
    end
  end

  defp handle_redemption_event(
         "confirm_redemption",
         %{"action_id" => action_id, "transaction_hash" => hash},
         socket
       ) do
    case socket.assigns.redemption_prepared do
      %{action_id: ^action_id} = envelope ->
        confirm_redemption(socket, envelope, hash)

      _ ->
        {:noreply,
         assign(socket,
           redemption_notice: %{
             tone: :error,
             message: "This wallet result does not match the reviewed action."
           }
         )}
    end
  end

  defp handle_redemption_event("retry_redemption_confirmation", _params, socket) do
    with %{action_id: action_id} = envelope <- socket.assigns.redemption_prepared,
         %{action_id: ^action_id, transaction_hash: hash} when is_binary(hash) <-
           socket.assigns.redemption_submission do
      confirm_redemption(socket, envelope, hash)
    else
      _ -> {:noreply, socket}
    end
  end

  defp handle_redemption_event("cancel_redemption_review", _params, socket) do
    if is_nil(socket.assigns.redemption_submission) do
      {:noreply,
       socket
       |> cancel_redemption_expiry()
       |> assign(
         redemption_prepared: nil,
         redemption_signing?: false,
         redemption_notice: %{tone: :info, message: "The wallet review was cancelled."}
       )
       |> push_event("redemption:abandoned", %{})}
    else
      {:noreply, socket}
    end
  end

  defp handle_redemption_event("refresh_redemption", _params, socket) do
    socket =
      if match?(%{status: :confirmed}, socket.assigns.redemption_submission) do
        assign(socket,
          redemption_submission: nil,
          redemption_notice: nil
        )
      else
        socket
      end

    {:noreply, start_redemption_read(socket)}
  end

  defp handle_redemption_event("redemption_wallet_failed", %{"message" => message}, socket) do
    notice =
      if socket.assigns.redemption_submission do
        %{tone: :info, message: "Transaction submitted. Verification can be retried safely."}
      else
        message =
          if is_binary(message) and byte_size(message) <= 180,
            do: message,
            else: "The wallet action did not complete."

        %{tone: :error, message: message}
      end

    {:noreply, assign(socket, redemption_signing?: false, redemption_notice: notice)}
  end

  defp handle_redemption_expiry(action_id, socket) do
    case {socket.assigns.redemption_prepared, socket.assigns.redemption_submission} do
      {%{action_id: ^action_id}, nil} ->
        {:noreply,
         socket
         |> cancel_redemption_expiry()
         |> assign(
           redemption_prepared: nil,
           redemption_signing?: false,
           redemption_notice: %{
             tone: :info,
             message: "This wallet review expired. Prepare the action again when ready."
           }
         )
         |> push_event("redemption:abandoned", %{})}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.shell
      route_spec={@route_spec}
      app_targets={@app_targets}
      account_control={@account_control}
      content_status={@content_status}
      presentation={@presentation}
      formation_panel={@formation_panel}
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
          buyback_fields={@autolaunch_buyback_fields}
          buyback_notice={@autolaunch_buyback_notice}
          buyback_prepared={@autolaunch_buyback_prepared}
          buyback_submission={@autolaunch_buyback_submission}
          buyback_signing={@autolaunch_buyback_signing?}
          bid_positions={@autolaunch_bid_positions}
          returnable_positions={@autolaunch_returnable_positions}
          claimed_token_positions={@autolaunch_claimed_token_positions}
          bid_fields={@autolaunch_bid_fields}
          bid_quote={@autolaunch_bid_quote}
          bid_notice={@autolaunch_bid_notice}
          bid_prepared={@autolaunch_bid_prepared}
          bid_submission={@autolaunch_bid_submission}
          bid_signing={@autolaunch_bid_signing?}
          launch_drafts={@autolaunch_launch_drafts}
          draft_fields={@autolaunch_draft_fields}
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

        <FormationLive.page
          :if={@route_spec.route_id == :formation}
          account_control={@account_control}
          regent={@regent}
          regent_status={@regent_status}
          regent_notice={@regent_notice}
          formation_fields={@formation_fields}
          cloud_runtime={@cloud_runtime}
          cloud_status={@cloud_status}
          cloud_notice={@cloud_notice}
        />

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

        <SettingsLive.page :if={@route_spec.route_id == :settings} />

        <.page
          :if={@route_spec.route_id == :stake}
          staking={@staking}
          status={@staking_status}
          authenticated={authenticated?(@access_context)}
          amount={@staking_amount}
          notice={@staking_notice}
          prepared={@staking_prepared}
          submission={@staking_submission}
          signing={@staking_signing?}
        />

        <.redemption_page
          :if={@route_spec.route_id == :redeem}
          redemption={@redemption}
          status={@redemption_status}
          authenticated={authenticated?(@access_context)}
          collection={@redemption_collection}
          token_id={@redemption_token_id}
          notice={@redemption_notice}
          prepared={@redemption_prepared}
          submission={@redemption_submission}
          signing={@redemption_signing?}
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

  defp initial_formation_panel(%{local_state: %{panel: %{default: panel}}}), do: panel
  defp initial_formation_panel(_route_spec), do: :none

  defp maybe_start_staking(socket, %{route_id: route_id}, generation)
       when route_id in [:app, :stake] do
    actor = staking_actor(socket)

    socket
    |> cancel_staking_confirmation()
    |> assign(staking: nil, staking_status: :loading)
    |> start_async({:staking, generation}, fn ->
      result = if actor, do: Staking.account(actor: actor), else: Staking.overview()
      {generation, result}
    end)
  end

  defp maybe_start_staking(socket, _route_spec, _generation) do
    socket
    |> cancel_staking_confirmation()
    |> assign(
      staking: nil,
      staking_status: :loading,
      staking_notice: nil,
      staking_signing?: false
    )
  end

  defp current_account(%{principal: {:human, account}}), do: account
  defp current_account(_access_context), do: nil

  defp current_human_id(%{principal: {:human, account}}), do: account.id
  defp current_human_id(_access_context), do: nil

  defp load_regent_route(socket, %{route_id: :formation}, _params) do
    regent = socket.assigns.current_regent

    socket = assign(socket, regent: regent, regent_status: if(regent, do: :ready, else: :empty))

    case human_actor(socket) do
      %Human{} = actor when not is_nil(regent) ->
        case Formation.get_my_cloud_runtime(actor: actor) do
          {:ok, []} -> assign(socket, cloud_runtime: nil, cloud_status: :empty)
          {:ok, [runtime]} -> assign(socket, cloud_runtime: runtime, cloud_status: :ready)
          {:error, _error} -> assign(socket, cloud_runtime: nil, cloud_status: :error)
        end

      _actor ->
        assign(socket, cloud_runtime: nil, cloud_status: :empty)
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

  defp load_techtree_route(socket, %{route_id: :techtree}, _params) do
    case Techtree.list_trees() do
      {:ok, trees} ->
        assign(socket,
          techtree_trees: trees,
          techtree_tree: nil,
          techtree_nodes: [],
          techtree_edges: [],
          techtree_node: nil,
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
        techtree_nodes: nodes,
        techtree_edges: edges,
        techtree_node: nil,
        techtree_notebook_artifact: nil,
        techtree_status: :ready
      )
    else
      {:ok, nil} ->
        assign(socket,
          techtree_tree: nil,
          techtree_nodes: [],
          techtree_edges: [],
          techtree_notebook_artifact: nil,
          techtree_status: :empty
        )

      {:error, _error} ->
        assign(socket,
          techtree_tree: nil,
          techtree_nodes: [],
          techtree_edges: [],
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
          techtree_notebook_artifact: nil,
          techtree_status: :empty
        )

      {:ok, node} ->
        assign(socket,
          techtree_node: node,
          techtree_edges: [],
          techtree_notebook_artifact: current_notebook_artifact(node),
          techtree_status: :ready
        )

      {:error, _error} ->
        assign(socket,
          techtree_node: nil,
          techtree_edges: [],
          techtree_notebook_artifact: nil,
          techtree_status: :empty
        )
    end
  end

  defp load_techtree_route(socket, _route_spec, _params), do: socket

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
        positions =
          case human_actor(socket) do
            %Human{} = actor ->
              case Autolaunch.list_my_bid_positions(actor: actor) do
                {:ok, records} -> Enum.filter(records, &(&1.auction_id == record.id))
                _ -> []
              end

            nil ->
              []
          end

        assign(socket,
          autolaunch_record: record,
          autolaunch_bid_positions: positions,
          autolaunch_status: :ready
        )

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

  defp regent_saved(socket, regent, message) do
    assign(socket,
      account_control:
        AshPlatform.AccessContext.account_control(socket.assigns.access_context, regent),
      current_regent: regent,
      formation_fields: %{"display_name" => "", "slug" => ""},
      regent: regent,
      regent_notice: %{tone: :success, message: message},
      regent_status: :ready
    )
  end

  defp human_actor(%{assigns: %{access_context: %{principal: {:human, account}}}}),
    do: %Human{human_account_id: account.id}

  defp human_actor(_socket), do: nil

  defp empty_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp maybe_start_redemption(socket, %{route_id: :redeem}, _content_generation),
    do: start_redemption_read(socket)

  defp maybe_start_redemption(socket, _route_spec, _content_generation) do
    socket
    |> cancel_redemption_read()
    |> cancel_redemption_confirmation()
    |> assign(
      redemption: nil,
      redemption_status: :loading,
      redemption_notice: nil,
      redemption_signing?: false
    )
  end

  defp start_redemption_read(socket) do
    socket = cancel_redemption_read(socket)
    generation = socket.assigns.redemption_generation + 1
    name = {:redemption, generation}
    actor = staking_actor(socket)
    collection = socket.assigns.redemption_collection
    token_id = parsed_token_id(socket.assigns.redemption_token_id)

    socket
    |> assign(
      redemption: nil,
      redemption_status: :loading,
      redemption_generation: generation,
      redemption_async_name: name
    )
    |> start_async(name, fn ->
      result =
        if actor,
          do: Redemption.account(collection, token_id, actor: actor),
          else: Redemption.overview()

      {generation, result}
    end)
  end

  defp cancel_redemption_read(%{assigns: %{redemption_async_name: nil}} = socket), do: socket

  defp cancel_redemption_read(socket) do
    socket
    |> cancel_async(socket.assigns.redemption_async_name)
    |> assign(redemption_async_name: nil)
  end

  defp cancel_redemption_confirmation(%{assigns: %{redemption_confirmation_name: nil}} = socket),
    do: socket

  defp cancel_redemption_confirmation(socket) do
    socket
    |> cancel_async(socket.assigns.redemption_confirmation_name)
    |> assign(redemption_confirmation_name: nil)
  end

  defp prepare_redemption(action, socket) do
    actor = staking_actor(socket)
    wallet = expected_wallet(socket)
    collection = socket.assigns.redemption_collection
    token_id = parsed_token_id(socket.assigns.redemption_token_id)

    case action do
      "approve_nft_collection" ->
        Redemption.prepare_nft_approval(wallet, collection, actor: actor)

      "approve_exact_usdc" ->
        Redemption.prepare_usdc_approval(wallet, actor: actor)

      "redeem" when is_integer(token_id) ->
        Redemption.prepare_redeem(wallet, collection, token_id, actor: actor)

      "claim" ->
        Redemption.prepare_claim(wallet, actor: actor)

      _ ->
        {:error, :invalid_selection}
    end
  end

  defp confirm_redemption(socket, envelope, transaction_hash) do
    if valid_transaction_hash?(transaction_hash) do
      actor = staking_actor(socket)
      name = {:redemption_confirmation, envelope.action_id}

      {:noreply,
       socket
       |> assign(
         redemption_confirmation_name: name,
         redemption_signing?: true,
         redemption_notice: %{tone: :info, message: "Confirming this transaction on Base…"}
       )
       |> start_async(name, fn ->
         Redemption.confirm_wallet_action(envelope, transaction_hash, actor: actor)
       end)}
    else
      {:noreply,
       assign(socket,
         redemption_signing?: false,
         redemption_notice: %{tone: :error, message: "The transaction hash is invalid."}
       )}
    end
  end

  defp schedule_redemption_expiry(socket, envelope) do
    socket = cancel_redemption_expiry(socket)

    case DateTime.from_iso8601(envelope.expires_at) do
      {:ok, expires_at, _offset} ->
        milliseconds = max(DateTime.diff(expires_at, Envelope.current_time(), :millisecond), 0)

        ref =
          Process.send_after(
            self(),
            {:redemption_envelope_expired, envelope.action_id},
            milliseconds
          )

        assign(socket, redemption_expiry_ref: ref)

      _ ->
        socket
    end
  end

  defp cancel_redemption_expiry(%{assigns: %{redemption_expiry_ref: nil}} = socket), do: socket

  defp cancel_redemption_expiry(socket) do
    Process.cancel_timer(socket.assigns.redemption_expiry_ref)
    assign(socket, redemption_expiry_ref: nil)
  end

  defp redemption_locked?(socket),
    do:
      not is_nil(socket.assigns.redemption_prepared) or
        match?(%{status: status} when status != :confirmed, socket.assigns.redemption_submission)

  defp parsed_token_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {token_id, ""} when token_id in 1..999 -> token_id
      _ -> nil
    end
  end

  defp parsed_token_id(_value), do: nil

  defp preparation_error(:nft_not_owned),
    do: "This wallet does not own the selected Animata token."

  defp preparation_error(:nft_approval_required), do: "Approve the selected NFT collection first."
  defp preparation_error(:insufficient_usdc), do: "This wallet needs at least 80 USDC."

  defp preparation_error(:exact_usdc_approval_required),
    do: "Set the USDC allowance to exactly 80 USDC before redeeming."

  defp preparation_error(:nothing_claimable), do: "No REGENT is unlocked to claim yet."

  defp preparation_error(_reason),
    do: "That action could not be prepared. Check the wallet and selection."

  defp cancel_staking_confirmation(%{assigns: %{staking_confirmation_name: nil}} = socket),
    do: socket

  defp cancel_staking_confirmation(%{assigns: %{staking_confirmation_name: name}} = socket) do
    socket |> cancel_async(name) |> assign(staking_confirmation_name: nil)
  end

  defp staking_actor(%{assigns: %{access_context: %{principal: {:human, account}}}}),
    do: %Human{human_account_id: account.id}

  defp staking_actor(_socket), do: nil

  defp authenticated?(%{principal: {:human, _account}}), do: true
  defp authenticated?(_access_context), do: false

  defp expected_wallet(%{assigns: %{access_context: %{principal: {:human, account}}}}),
    do: account.wallet_address

  defp expected_wallet(_socket), do: nil

  defp prepare_staking(action, amount, socket) do
    actor = staking_actor(socket)
    wallet = expected_wallet(socket)

    case action do
      "stake" -> Staking.prepare_stake(wallet, amount, actor: actor)
      "unstake" -> Staking.prepare_unstake(wallet, amount, actor: actor)
      "claim_usdc" -> Staking.prepare_claim_usdc(wallet, actor: actor)
      "claim_regent" -> Staking.prepare_claim_regent(wallet, actor: actor)
      "claim_and_restake_regent" -> Staking.prepare_claim_and_restake_regent(wallet, actor: actor)
      _ -> {:error, :unknown_action}
    end
  end

  defp prepare_autolaunch_review(socket, {:ok, envelope}, fields) do
    {:noreply,
     socket
     |> assign(
       autolaunch_bid_fields: fields,
       autolaunch_bid_prepared: envelope,
       autolaunch_bid_submission: nil,
       autolaunch_bid_signing?: false,
       autolaunch_bid_notice: %{
         tone: :info,
         message: "Review the details before opening your wallet."
       }
     )
     |> schedule_autolaunch_bid_expiry(envelope)}
  end

  defp prepare_autolaunch_review(socket, {:error, _reason}, fields) do
    {:noreply,
     assign(socket,
       autolaunch_bid_fields: fields,
       autolaunch_bid_prepared: nil,
       autolaunch_bid_notice: %{
         tone: :error,
         message: "That auction action could not be prepared. Check the amount and wallet."
       }
     )}
  end

  defp prepare_autolaunch_buyback_review(socket, {:ok, envelope}, fields) do
    {:noreply,
     socket
     |> assign(
       autolaunch_buyback_fields: fields,
       autolaunch_buyback_prepared: envelope,
       autolaunch_buyback_submission: nil,
       autolaunch_buyback_signing?: false,
       autolaunch_buyback_notice: %{
         tone: :info,
         message: "Review the settlement details before opening your wallet."
       }
     )
     |> schedule_autolaunch_buyback_expiry(envelope)}
  end

  defp prepare_autolaunch_buyback_review(
         socket,
         {:error, :buyback_market_paused},
         fields
       ) do
    {:noreply,
     assign(socket,
       autolaunch_buyback_fields: fields,
       autolaunch_buyback_prepared: nil,
       autolaunch_buyback_notice: %{
         tone: :error,
         message: "This market is temporarily paused. Try again after prices refresh."
       }
     )}
  end

  defp prepare_autolaunch_buyback_review(socket, {:error, _reason}, fields) do
    {:noreply,
     assign(socket,
       autolaunch_buyback_fields: fields,
       autolaunch_buyback_prepared: nil,
       autolaunch_buyback_notice: %{
         tone: :error,
         message: "That settlement could not be prepared. Check the amount and wallet."
       }
     )}
  end

  defp confirm_autolaunch_bid(socket, envelope, transaction_hash, approval_hash) do
    if valid_transaction_hash?(transaction_hash) and
         (is_nil(approval_hash) or valid_transaction_hash?(approval_hash)) do
      actor = human_actor(socket)
      name = {:autolaunch_bid_confirmation, envelope.action_id}

      {:noreply,
       socket
       |> assign(
         autolaunch_bid_confirmation_name: name,
         autolaunch_bid_signing?: true,
         autolaunch_bid_notice: %{
           tone: :info,
           message: "Confirming this transaction on Base…"
         }
       )
       |> start_async(name, fn ->
         Autolaunch.confirm_bid_wallet_action(
           envelope,
           transaction_hash,
           approval_hash,
           actor: actor
         )
       end)}
    else
      {:noreply,
       assign(socket,
         autolaunch_bid_signing?: false,
         autolaunch_bid_notice: %{tone: :error, message: "The transaction hash is invalid."}
       )}
    end
  end

  defp confirm_autolaunch_buyback(socket, envelope, transaction_hash) do
    if valid_transaction_hash?(transaction_hash) do
      actor = human_actor(socket)
      name = {:autolaunch_buyback_confirmation, envelope.action_id}

      {:noreply,
       socket
       |> assign(
         autolaunch_buyback_confirmation_name: name,
         autolaunch_buyback_signing?: true,
         autolaunch_buyback_notice: %{
           tone: :info,
           message: "Confirming this transaction on Base…"
         }
       )
       |> start_async(name, fn ->
         Autolaunch.confirm_buyback_wallet_action(
           envelope,
           transaction_hash,
           actor: actor
         )
       end)}
    else
      {:noreply,
       assign(socket,
         autolaunch_buyback_signing?: false,
         autolaunch_buyback_notice: %{
           tone: :error,
           message: "The transaction hash is invalid."
         }
       )}
    end
  end

  defp start_autolaunch_approval_verification(socket, envelope, hash) do
    actor = human_actor(socket)
    name = {:autolaunch_bid_approval_status, envelope.action_id}

    socket
    |> assign(
      autolaunch_bid_signing?: true,
      autolaunch_bid_notice: %{
        tone: :info,
        message: "Verifying the quote-token approval on Base…"
      }
    )
    |> start_async(name, fn ->
      Autolaunch.verify_bid_approval_submission(envelope, hash, actor: actor)
    end)
  end

  defp autolaunch_wallet_window_open?(envelope) do
    with true <- Envelope.valid?(envelope),
         {:ok, expires_at, _offset} <- DateTime.from_iso8601(envelope.expires_at) do
      DateTime.diff(expires_at, Envelope.current_time(), :second) >
        @autolaunch_wallet_open_minimum_seconds
    else
      _ -> false
    end
  end

  defp autolaunch_approval_authorized?(%{approval: nil}, _submission), do: true
  defp autolaunch_approval_authorized?(_envelope, nil), do: true

  defp autolaunch_approval_authorized?(_envelope, %{status: :approval_verified}),
    do: true

  defp autolaunch_approval_authorized?(_envelope, _submission), do: false

  defp autolaunch_submission_hash?(%{approval_transaction_hash: hash}) when is_binary(hash),
    do: true

  defp autolaunch_submission_hash?(%{transaction_hash: hash}) when is_binary(hash), do: true
  defp autolaunch_submission_hash?(_submission), do: false

  defp schedule_autolaunch_bid_expiry(socket, envelope) do
    socket = cancel_autolaunch_bid_expiry(socket)

    case DateTime.from_iso8601(envelope.expires_at) do
      {:ok, expires_at, _offset} ->
        milliseconds = max(DateTime.diff(expires_at, Envelope.current_time(), :millisecond), 0)

        ref =
          Process.send_after(
            self(),
            {:autolaunch_bid_envelope_expired, envelope.action_id},
            milliseconds
          )

        assign(socket, autolaunch_bid_expiry_ref: ref)

      _ ->
        socket
    end
  end

  defp cancel_autolaunch_bid_expiry(%{assigns: %{autolaunch_bid_expiry_ref: nil}} = socket),
    do: socket

  defp cancel_autolaunch_bid_expiry(socket) do
    Process.cancel_timer(socket.assigns.autolaunch_bid_expiry_ref)
    assign(socket, autolaunch_bid_expiry_ref: nil)
  end

  defp schedule_autolaunch_buyback_expiry(socket, envelope) do
    socket = cancel_autolaunch_buyback_expiry(socket)

    case DateTime.from_iso8601(envelope.expires_at) do
      {:ok, expires_at, _offset} ->
        milliseconds = max(DateTime.diff(expires_at, Envelope.current_time(), :millisecond), 0)

        ref =
          Process.send_after(
            self(),
            {:autolaunch_buyback_envelope_expired, envelope.action_id},
            milliseconds
          )

        assign(socket, autolaunch_buyback_expiry_ref: ref)

      _ ->
        socket
    end
  end

  defp cancel_autolaunch_buyback_expiry(
         %{assigns: %{autolaunch_buyback_expiry_ref: nil}} = socket
       ),
       do: socket

  defp cancel_autolaunch_buyback_expiry(socket) do
    Process.cancel_timer(socket.assigns.autolaunch_buyback_expiry_ref)
    assign(socket, autolaunch_buyback_expiry_ref: nil)
  end

  defp expired_autolaunch_buyback_review(socket) do
    {:noreply,
     socket
     |> cancel_autolaunch_buyback_expiry()
     |> assign(
       autolaunch_buyback_prepared: nil,
       autolaunch_buyback_submission: nil,
       autolaunch_buyback_signing?: false,
       autolaunch_buyback_notice: %{
         tone: :info,
         message: "This wallet review expired. Prepare the buyback settlement again when ready."
       }
     )
     |> push_event("autolaunch-buyback:abandoned", %{})}
  end

  defp expired_autolaunch_review(socket) do
    approval_submitted? =
      match?(
        %{approval_transaction_hash: hash} when is_binary(hash),
        socket.assigns.autolaunch_bid_submission
      )

    message =
      if approval_submitted? do
        "This review expired before the auction action was sent. The exact quote-token approval may remain onchain; review it in your wallet before preparing again."
      else
        "This wallet review expired. Prepare the auction action again when ready."
      end

    {:noreply,
     socket
     |> cancel_autolaunch_bid_expiry()
     |> assign(
       autolaunch_bid_prepared: nil,
       autolaunch_bid_submission: nil,
       autolaunch_bid_signing?: false,
       autolaunch_bid_notice: %{tone: :info, message: message}
     )
     |> push_event("autolaunch-bid:abandoned", %{})}
  end

  defp cancel_autolaunch_approval(socket) do
    submission = socket.assigns.autolaunch_bid_submission
    hash = short_hash(submission[:approval_transaction_hash])

    message =
      if submission[:status] == :approval_verified do
        "The bid was not sent. The exact quote-token allowance remains onchain."
      else
        "The bid was not sent. Approval transaction #{hash} may still confirm later; check it in your wallet or on Base before relying on the allowance state."
      end

    socket
    |> cancel_autolaunch_bid_expiry()
    |> assign(
      autolaunch_bid_prepared: nil,
      autolaunch_bid_submission: nil,
      autolaunch_bid_signing?: false,
      autolaunch_bid_notice: %{tone: :info, message: message}
    )
    |> push_event("autolaunch-bid:abandoned", %{})
  end

  defp autolaunch_submitted_copy("approval", hash),
    do: "Exact quote-token approval submitted: #{short_hash(hash)}"

  defp autolaunch_submitted_copy("action", hash),
    do: "Auction transaction submitted: #{short_hash(hash)}"

  defp autolaunch_submitted_copy(_phase, _hash), do: "Transaction submitted."

  defp confirm_staking(socket, envelope, transaction_hash) do
    actor = staking_actor(socket)
    name = {:staking_confirmation, envelope.action_id}
    approval_hash = (socket.assigns.staking_submission || %{})[:approval_transaction_hash]

    {:noreply,
     socket
     |> assign(staking_confirmation_name: name)
     |> assign(staking_notice: %{tone: :info, message: "Confirming this transaction on Base…"})
     |> start_async(name, fn ->
       Staking.confirm_wallet_action(envelope, transaction_hash, approval_hash, actor: actor)
     end)}
  end

  defp schedule_staking_expiry(socket, envelope) do
    socket = cancel_staking_expiry(socket)

    case DateTime.from_iso8601(envelope.expires_at) do
      {:ok, expires_at, _offset} ->
        milliseconds = max(DateTime.diff(expires_at, Envelope.current_time(), :millisecond), 0)

        ref =
          Process.send_after(
            self(),
            {:staking_envelope_expired, envelope.action_id},
            milliseconds
          )

        assign(socket, staking_expiry_ref: ref)

      _ ->
        socket
    end
  end

  defp cancel_staking_expiry(%{assigns: %{staking_expiry_ref: nil}} = socket), do: socket

  defp cancel_staking_expiry(socket) do
    Process.cancel_timer(socket.assigns.staking_expiry_ref)
    assign(socket, staking_expiry_ref: nil)
  end

  defp abandon_approval(socket, reason) do
    submission = socket.assigns.staking_submission
    hash = short_hash(submission[:approval_transaction_hash])

    message =
      case {reason, submission[:status]} do
        {:expired, :approval_verified} ->
          "This approval review expired. No staking transaction was sent. The exact REGENT allowance remains onchain."

        {:user, :approval_verified} ->
          "Staking was not sent. The exact REGENT allowance remains onchain. You can prepare a new action."

        {:expired, _pending} ->
          "This approval review expired and no staking transaction was sent. Approval transaction #{hash} may still confirm later. Check this hash in your wallet or on Base before relying on the allowance state."

        {:user, _pending} ->
          "Staking was not sent. Approval transaction #{hash} may still confirm later. Check this hash in your wallet or on Base before relying on the allowance state."
      end

    socket
    |> cancel_staking_expiry()
    |> assign(
      staking_prepared: nil,
      staking_submission: nil,
      staking_signing?: false,
      staking_notice: %{tone: :info, message: message}
    )
    |> push_event("staking:abandoned", %{})
  end

  defp start_approval_verification(socket, envelope, hash) do
    actor = staking_actor(socket)
    name = {:staking_approval_status, envelope.action_id}

    socket
    |> assign(
      staking_signing?: true,
      staking_notice: %{tone: :info, message: "Verifying the REGENT approval on Base…"}
    )
    |> start_async(name, fn ->
      Staking.verify_approval_submission(envelope, hash, actor: actor)
    end)
  end

  defp record_submission(nil, action_id, "approval", hash),
    do: %{action_id: action_id, approval_transaction_hash: hash, status: :approval_pending}

  defp record_submission(nil, action_id, "action", hash),
    do: %{action_id: action_id, transaction_hash: hash, status: :main_pending}

  defp record_submission(%{action_id: action_id} = submission, action_id, "approval", hash),
    do: Map.merge(submission, %{approval_transaction_hash: hash, status: :approval_pending})

  defp record_submission(%{action_id: action_id} = submission, action_id, "action", hash),
    do: Map.merge(submission, %{transaction_hash: hash, status: :main_pending})

  defp record_submission(submission, _action_id, _phase, _hash), do: submission

  defp submitted_copy("approval", hash), do: "REGENT approval submitted: #{short_hash(hash)}"
  defp submitted_copy("action", hash), do: "Staking transaction submitted: #{short_hash(hash)}"
  defp submitted_copy(_phase, _hash), do: "Transaction submitted."

  defp short_hash("0x" <> hash) when byte_size(hash) == 64,
    do: "0x#{String.slice(hash, 0, 6)}…#{String.slice(hash, -4, 4)}"

  defp short_hash(_hash), do: "transaction recorded"

  defp submitted_action?(%{action_id: action_id}, action_id), do: true
  defp submitted_action?(_submission, _action_id), do: false

  defp main_submitted?(%{transaction_hash: hash}) when is_binary(hash), do: true
  defp main_submitted?(_submission), do: false

  defp approval_authorized?(%{approval: nil}, _submission), do: true
  defp approval_authorized?(_envelope, nil), do: true
  defp approval_authorized?(_envelope, %{status: :approval_verified}), do: true
  defp approval_authorized?(_envelope, _submission), do: false

  defp pending_submission?(%{status: status})
       when status in [:approval_pending, :approval_verified, :main_pending],
       do: true

  defp pending_submission?(_submission), do: false

  defp valid_transaction_hash?("0x" <> hash),
    do: byte_size(hash) == 64 and String.match?(hash, ~r/^[0-9a-fA-F]+$/)

  defp valid_transaction_hash?(_hash), do: false
end
