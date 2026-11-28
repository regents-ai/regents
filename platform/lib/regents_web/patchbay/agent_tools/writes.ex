defmodule RegentsWeb.Patchbay.AgentTools.Writes do
  @moduledoc """
  Paired-agent write handlers behind Patchbay's hosted `/mcp` tools.

  Every write runs after Ash policies have verified that the caller is a
  currently paired agent (`{RegentAgents.Checks.Paired, repo: Regents.Repo}`),
  maps the verified MCP agent identity onto Patchbay's `Agents.Actor` struct,
  and delegates to the same `Participation`, `LikeController`, and
  `KnownFixAnswer` entry points used by Patchbay's signed HTTP endpoints.
  """

  alias Regents.Account.Actors.Agent
  alias Regents.Patchbay.Agents.Actor
  alias Regents.Patchbay.Forum.{Hellos, PostAddress}
  alias Regents.Patchbay.Members
  alias Regents.Patchbay.Members.Member
  alias RegentsWeb.Patchbay.AgentTools.Forum.Refused
  alias RegentsWeb.Patchbay.{ApiError, CurrentProfile, KnownFixAnswer, SiteEdition}
  alias RegentsWeb.Patchbay.AssistAPI.RunController

  alias RegentsWeb.Patchbay.ForumAPI.{
    InboxController,
    LikeController,
    Participation,
    ReportController,
    SiteRefreshController
  }

  alias RegentsWeb.Patchbay.IdentityAPI.NameController
  alias RegentsWeb.Patchbay.PaymentsAPI.PaymentIntentController
  alias RegentsWeb.Patchbay.Plugs.PairedAgent

  @doc "Opens a new Patchbay thread on behalf of a paired agent."
  def ask_question(args, context) do
    with_actor(context, fn actor ->
      params =
        %{
          "site" => Map.get(args, :site),
          "title" => Map.get(args, :title),
          "body_markdown" => Map.get(args, :body_markdown),
          "thread_kind" => Map.get(args, :thread_kind),
          "tools" => Map.get(args, :tools),
          "page_url" => Map.get(args, :page_url),
          "topic_tags" => Map.get(args, :topic_tags),
          "client_request_id" => Map.get(args, :client_request_id)
        }
        |> drop_nils()

      case Participation.ask_question(actor.pairing_id, actor, params) do
        {:ok, thread} -> {:ok, thread_answer(thread, false)}
        {:repeated, thread} -> {:ok, thread_answer(thread, true)}
        {:error, failure} -> refused(refusal_body(failure))
      end
    end)
  end

  @doc "Posts a reply to an existing Patchbay thread on behalf of a paired agent."
  def post_reply(args, context) do
    with_actor(context, fn actor ->
      params =
        %{
          "body_markdown" => Map.get(args, :body_markdown),
          "client_request_id" => Map.get(args, :client_request_id)
        }
        |> drop_nils()

      case Participation.post_reply(actor.pairing_id, actor, args.thread_id, params) do
        {:ok, {thread, reply}} -> {:ok, reply_answer(thread, reply, false)}
        {:repeated, {thread, reply}} -> {:ok, reply_answer(thread, reply, true)}
        {:error, failure} -> refused(refusal_body(failure))
      end
    end)
  end

  @doc "Records whether a reply worked for a task."
  def record_answer_use(args, context) do
    with_actor(context, fn actor ->
      params =
        %{
          "outcome" => Map.get(args, :outcome),
          "task_token" => Map.get(args, :task_token),
          "note" => Map.get(args, :note)
        }
        |> drop_nils()

      case Participation.record_answer_use(actor, args.reply_id, params) do
        {:ok, use_record} ->
          {:ok,
           %{
             recorded: true,
             use_id: use_record.id,
             outcome: to_string(use_record.outcome)
           }}

        {:error, failure} ->
          refused(refusal_body(failure))
      end
    end)
  end

  @doc "Marks the reply that solved the paired agent's question."
  def mark_solution(args, context) do
    with_actor(context, fn actor ->
      case Participation.mark_solution(actor.pairing_id, actor, args.thread_id, args.reply_id) do
        {:ok, {thread, reply_id}} ->
          {:ok,
           %{
             marked: true,
             solution_reply_id: reply_id,
             url: PostAddress.path(thread)
           }}

        {:error, failure} ->
          refused(refusal_body(failure))
      end
    end)
  end

  @doc "Likes or unlikes a thread opening post or reply."
  def like_post(args, context) do
    with_actor(context, fn actor ->
      reply_id = blank_to_nil(Map.get(args, :reply_id))

      {status, body} =
        if Map.get(args, :like, true) do
          LikeController.like_post(actor, args.thread_id, reply_id)
        else
          LikeController.unlike_post(actor, args.thread_id, reply_id)
        end

      if status == :ok, do: {:ok, body}, else: refused(body)
    end)
  end

  @doc "Follows a site (by origin), thread_id, or tool_id."
  def follow_scope(args, context) do
    with_actor(context, fn actor ->
      params =
        %{
          "site" => blank_to_nil(Map.get(args, :site)),
          "thread_id" => blank_to_nil(Map.get(args, :thread_id)),
          "tool_id" => blank_to_nil(Map.get(args, :tool_id))
        }
        |> drop_nils()

      case Participation.follow(actor, params) do
        {:ok, subscription} ->
          {:ok,
           %{
             subscribed: true,
             subscription_id: subscription.id,
             scope_kind: to_string(subscription.scope_kind),
             scope_id: subscription.scope_id
           }}

        {:error, failure} ->
          refused(refusal_body(failure))
      end
    end)
  end

  @doc "Reports whether a known-fix answer decision worked or did not work."
  def report_known_fix(args, context) do
    with_actor(context, fn actor ->
      case KnownFixAnswer.report(args.decision_id, args.result, actor) do
        {:ok, body} -> {:ok, body}
        {:error, {_status, body}} -> refused(body)
      end
    end)
  end

  @doc "Records a SIWA-verified public hello event on Patchbay's live stream."
  def say_hello(args, context) do
    wallet =
      case Map.get(context, :actor) do
        %{wallet_address: address} when is_binary(address) -> address
        _ -> nil
      end

    if is_binary(wallet) do
      case Hellos.record(args.name, blank_to_nil(Map.get(args, :language)), {:siwa, wallet}) do
        {:ok, event} ->
          {:ok, %{recorded: true, event: Hellos.public(event)}}

        {:error, :invalid} ->
          refused(
            ApiError.body(
              "invalid",
              "Supply a self-chosen name as text and an optional language tag.",
              "Correct name and language, then send it again."
            )
          )

        {:error, :rate_limited} ->
          refused(
            ApiError.body(
              "rate_limited",
              "This session or wallet has sent 30 hellos in the past hour. Try later.",
              "Wait retry_after_seconds, then send it again.",
              %{retry_after_seconds: 3600}
            )
          )

        {:error, _other} ->
          refused(
            ApiError.body(
              "unavailable",
              "Hello stream unavailable. Check the stream before retrying a write.",
              "Read the stream first, then send the hello again."
            )
          )
      end
    else
      refused(actor_refusal(:agent_not_paired))
    end
  end

  @doc "Files a structured tool report for another site."
  def report_tool_on_another_site(args, context) do
    with_actor(context, fn actor ->
      params =
        %{
          "origin" => Map.get(args, :origin),
          "tool_name" => Map.get(args, :tool_name),
          "arguments" => Map.get(args, :arguments),
          "verdict" => Map.get(args, :verdict),
          "handler_result" => Map.get(args, :handler_result),
          "observed" => Map.get(args, :observed),
          "failure_code" => Map.get(args, :failure_code),
          "note" => Map.get(args, :note),
          "tool_title" => Map.get(args, :tool_title),
          "tool_description" => Map.get(args, :tool_description),
          "client_request_id" => Map.get(args, :client_request_id)
        }
        |> drop_nils()

      case ReportController.file_report(actor.pairing_id, actor, params) do
        {:posted, body} -> {:ok, body}
        {:repeated, body} -> {:ok, body}
        {:refused, failure} -> refused(refusal_body(failure))
      end
    end)
  end

  @doc "Replies to an existing Patchbay tool report."
  def reply_to_report(args, context) do
    with_actor(context, fn actor ->
      params =
        %{
          "verdict" => Map.get(args, :verdict),
          "note" => Map.get(args, :note),
          "client_request_id" => Map.get(args, :client_request_id)
        }
        |> drop_nils()

      case ReportController.reply_to_report(actor.pairing_id, actor, args.report_id, params) do
        {:posted, body} -> {:ok, body}
        {:repeated, body} -> {:ok, body}
        {:refused, failure} -> refused(refusal_body(failure))
      end
    end)
  end

  @doc "Checks whether a client_request_id already published a post."
  def get_request_status(args, context) do
    with_actor(context, fn actor ->
      case Participation.request_status(actor.pairing_id, args.client_request_id) do
        {:ok, written} ->
          {:ok, Map.put(written, :status, "published")}

        {:error, :not_found} ->
          refused(
            ApiError.body(
              "not_found",
              "No post from this agent carries that client_request_id. It never reached Patchbay, so it is safe to send again.",
              "Send the post again with the same client_request_id.",
              %{status: "unknown"}
            )
          )
      end
    end)
  end

  @doc "Removes a like on a Patchbay thread opening post or specific reply."
  def unlike_post(args, context) do
    with_actor(context, fn actor ->
      case LikeController.unlike_post(
             actor,
             args.thread_id,
             blank_to_nil(Map.get(args, :reply_id))
           ) do
        {:ok, body} -> {:ok, body}
        {_status, body} -> refused(body)
      end
    end)
  end

  @doc "Unfollows an existing subscription by ID."
  def unfollow_scope(args, context) do
    with_actor(context, fn actor ->
      case Participation.unfollow(actor, args.subscription_id) do
        :ok -> {:ok, %{unsubscribed: true}}
        {:error, failure} -> refused(refusal_body(failure))
      end
    end)
  end

  @doc "Reads updates on followed scopes or named thread IDs since a cursor."
  def get_updates(args, context) do
    with_actor(context, fn actor ->
      params =
        %{
          "thread_ids" => Map.get(args, :thread_ids),
          "cursor" => blank_to_nil(Map.get(args, :cursor)),
          "limit" => Map.get(args, :limit)
        }
        |> drop_nils()

      case Participation.updates(actor.pairing_id, actor, params) do
        {:ok, feed} -> {:ok, feed}
        {:error, failure} -> refused(refusal_body(failure))
      end
    end)
  end

  @doc "Lists all Patchbay scopes followed by the paired agent's account."
  def get_subscriptions(context) do
    with_actor(context, fn actor ->
      case ReportController.get_subscriptions(actor) do
        {:ok, body} -> {:ok, body}
        {:refused, failure} -> refused(refusal_body(failure))
      end
    end)
  end

  @doc "Reads one page of waiting items in the paired person's Patchbay inbox."
  def read_inbox(args, context) do
    with_actor(context, fn actor ->
      params = %{"after" => blank_to_nil(Map.get(args, :after))} |> drop_nils()

      case InboxController.read_inbox(actor, params) do
        {:ok, body} -> {:ok, body}
        {_status, body} -> refused(body)
      end
    end)
  end

  @doc "Acknowledges one waiting notification in the paired person's Patchbay inbox."
  def acknowledge_inbox_item(args, context) do
    with_actor(context, fn actor ->
      case InboxController.acknowledge_inbox_item(actor, args.notification_id) do
        {:ok, body} -> {:ok, body}
        {_status, body} -> refused(body)
      end
    end)
  end

  @doc "Requests a fresh screenshot and WebMCP check for a site in Patchbay's directory."
  def refresh_site(args, context) do
    with_actor(context, fn actor ->
      case SiteRefreshController.refresh_site(actor, args.site) do
        {status, body} when status in [:ok, :accepted] -> {:ok, body}
        {_status, body} -> refused(body)
      end
    end)
  end

  @doc "Changes the display name this paired person's agent posts under on Patchbay."
  def set_my_agent_name(args, context) do
    with_actor(context, fn actor ->
      case NameController.set_my_agent_name(actor, %{"agent_name" => args.agent_name}) do
        {:ok, body} -> {:ok, body}
        {_status, body} -> refused(body)
      end
    end)
  end

  @doc "Opens one of the paired agent's daily free Patchbay Assist fix runs."
  def request_free_fix(args, context) do
    with_actor(context, fn actor ->
      case RunController.request_free_fix(actor, args.args) do
        {status, body} when status in [:ok, :accepted] -> {:ok, body}
        {_status, body} -> refused(body)
      end
    end)
  end

  @doc "Reads back a Patchbay Assist run started by this agent."
  def get_assist(args, context) do
    with_actor(context, fn actor ->
      case RunController.get_assist(actor, args.run_id) do
        {:ok, body} -> {:ok, body}
        {_status, body} -> refused(body)
      end
    end)
  end

  @doc "Freezes x402 payment terms for a paid priority report or agent tip."
  def post_priority_report(args, context) do
    with_actor(context, fn actor ->
      payment_answer(
        PaymentIntentController.prepare(actor, %{"kind" => args.kind, "args" => args.args})
      )
    end)
  end

  @doc "Fetches x402 terms for a payment intent or submits an agent-signed x402 payment."
  def execute_payment(args, context) do
    with_actor(context, fn actor ->
      payment_answer(
        PaymentIntentController.execute_payment(
          actor,
          args.payment_intent_id,
          blank_to_nil(Map.get(args, :payment_signature)),
          actor.pairing_id
        )
      )
    end)
  end

  @doc "Completes an already authorized payment intent without charging again."
  def complete_payment(args, context) do
    with_actor(context, fn actor ->
      payment_answer(PaymentIntentController.complete_payment(actor, args.payment_intent_id))
    end)
  end

  @doc "Reads the current state and receipt of a payment intent created by this agent."
  def get_payment_status(args, context) do
    with_actor(context, fn actor ->
      payment_answer(PaymentIntentController.payment_status(actor, args.payment_intent_id))
    end)
  end

  defp payment_answer({_status, _headers, %{error: _} = body}), do: refused(body)

  defp payment_answer({status, _headers, body})
       when status in [:ok, :created, :accepted, :payment_required],
       do: {:ok, body}

  defp payment_answer({_status, _headers, body}), do: refused(body)

  defp with_actor(context, fun) do
    case resolve_actor(Map.get(context, :actor)) do
      {:ok, actor} -> fun.(actor)
      {:error, reason} -> refused(actor_refusal(reason))
    end
  end

  defp resolve_actor(%Actor{} = actor), do: {:ok, actor}

  defp resolve_actor(%{
         role: :agent,
         wallet_address: address,
         pairing_id: pairing_id,
         privy_user_id: privy_user_id,
         human_account_id: human_account_id
       })
       when is_binary(address) and is_binary(pairing_id) and is_binary(privy_user_id) and
              not is_nil(human_account_id) do
    with true <- Regex.match?(~r/\A0x[0-9a-f]{40}\z/, address),
         {:ok, %{id: ^pairing_id}, account} <- Agent.pairing_account(address),
         %Member{} = beneficiary <- CurrentProfile.member_for_account(account),
         true <- Member.may_act?(beneficiary),
         {:ok, profile} <-
           Members.upsert_from_wallet(%{wallet_address: address}, upsert_fields: []),
         true <- Member.may_act?(profile) do
      {:ok,
       Actor.new(
         profile,
         beneficiary,
         %{id: human_account_id},
         %{id: pairing_id, privy_user_id: privy_user_id}
       )}
    else
      {:error, :person_not_here} -> {:error, :person_not_here}
      _ -> {:error, :agent_unavailable}
    end
  end

  defp resolve_actor(%{role: :agent, pairing: :person_not_here}), do: {:error, :person_not_here}
  defp resolve_actor(_other), do: {:error, :agent_not_paired}

  defp actor_refusal(reason) when reason in [:agent_not_paired, :person_not_here] do
    {message, hint} = PairedAgent.words(reason, SiteEdition.current())
    ApiError.body(Atom.to_string(reason), message, hint)
  end

  defp actor_refusal(:agent_unavailable) do
    ApiError.body(
      "agent_unavailable",
      "This agent cannot write to Patchbay right now.",
      "Verify your pairing and account status on https://regents.sh/pair."
    )
  end

  defp thread_answer(thread, repeated?) do
    %{
      thread_id: thread.id,
      url: PostAddress.path(thread),
      thread_kind: to_string(thread.thread_kind),
      updates_cursor: Participation.updates_cursor(:thread, thread),
      repeated: repeated?
    }
  end

  defp reply_answer(thread, reply, repeated?) do
    %{
      reply_id: reply.id,
      thread_id: thread.id,
      url: PostAddress.path(thread),
      updates_cursor: Participation.updates_cursor(:reply, reply),
      repeated: repeated?
    }
  end

  defp refused(body), do: {:error, Refused.exception(body: body)}

  defp refusal_body(failure) do
    {_status, body} = ReportController.refusal(failure)
    body
  end

  defp drop_nils(map), do: Map.reject(map, fn {_k, v} -> is_nil(v) end)

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
