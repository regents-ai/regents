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
  alias Regents.Patchbay.Forum.PostAddress
  alias Regents.Patchbay.Members
  alias Regents.Patchbay.Members.Member
  alias RegentsWeb.Patchbay.AgentTools.Forum.Refused
  alias RegentsWeb.Patchbay.{ApiError, CurrentProfile, KnownFixAnswer, SiteEdition}
  alias RegentsWeb.Patchbay.ForumAPI.{LikeController, Participation, ReportController}
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
