defmodule RegentsWeb.AgentTools.Account do
  @moduledoc """
  Paired-agent hosted MCP tool actions for core Regents at `/mcp`: identity
  probe (`whoami`), check-in (`status`), account summary, verified name claims,
  staking position, Regent Points, and private team messages.
  """

  use Ash.Resource,
    otp_app: :regents,
    domain: RegentsWeb.AgentTools,
    authorizers: [Ash.Policy.Authorizer]

  alias RegentAgents.{Agent, Broker, HTTP, HumanBacking}
  alias RegentPoints.{Rules, Seasons}
  alias Regents.Account.{Accounts, AgentAccount, Names}
  alias Regents.Account.Points.Board
  alias Regents.Messages
  alias Regents.Messages.Refused, as: MessageRefused
  alias Regents.SharedReading
  alias Regents.Stake
  alias Regents.Stake.{Facts, SnapshotCache}
  alias RegentsWeb.Account.PointsEntries
  alias RegentsWeb.AgentTools.Public.Refused
  alias RegentsWeb.Chain.ReadBudget
  alias RegentsWeb.FormErrors

  @points_off "Earning Points is off on this site."

  actions do
    action :whoami, :map do
      description "Check your SIWA identity, pairing status, allowed actions, and next step."

      run fn _input, %{actor: actor} ->
        regent_agent = %Agent{
          wallet: actor.wallet_address,
          chain_id: actor.chain_id || 8453
        }

        case RegentAgents.current_pairing(actor: regent_agent) do
          {:ok, pairing} ->
            status = pairing_status(pairing)

            {:ok,
             %{
               data: %{
                 agent: %{wallet: actor.wallet_address, registry_listing: nil},
                 audience: Broker.audience(),
                 authenticated: true,
                 pairing:
                   if(pairing, do: %{id: pairing.id, paired_at: pairing.paired_at}, else: nil),
                 status: status,
                 allowed: Map.fetch!(Application.fetch_env!(:regent_agents, :allowed), status),
                 next_step: HTTP.next_step(status)
               }
             }}

          {:error, _} ->
            refused(
              "unavailable",
              "Your pairing could not be read right now.",
              "Try again in a moment."
            )
        end
      end
    end

    action :status, :map do
      description "Check in as a paired agent and read the account you act for."

      run fn _input, %{actor: actor} ->
        regent_agent = %Agent{
          wallet: actor.wallet_address,
          chain_id: actor.chain_id || 8453
        }

        with {:ok, %{privy_user_id: privy_user_id}} <-
               RegentAgents.current_pairing(actor: regent_agent),
             %{} = account <- AgentAccount.account(privy_user_id),
             {:ok, paired} <- RegentAgents.check_in_agent(privy_user_id, actor: regent_agent) do
          {:ok,
           %{
             data:
               %{
                 id: paired.id,
                 name: paired.name,
                 harness: paired.harness,
                 wallet: paired.wallet,
                 paired_at: DateTime.to_iso8601(paired.paired_at),
                 last_contact_at: DateTime.to_iso8601(paired.last_contact_at),
                 registry_listing: nil,
                 account: account
               }
               |> Map.merge(HumanBacking.describe(paired))
           }}
        else
          {:ok, nil} ->
            refused(
              "agent_not_paired",
              "This agent is not paired with an account.",
              "Ask your person to pair you on https://regents.sh/account/agents."
            )

          nil ->
            refused(
              "person_not_here",
              "The person this agent is paired with hasn't signed in on this site yet.",
              "Ask your person to sign in on https://regents.sh once, then retry."
            )

          {:error, _} ->
            refused(
              "agent_not_paired",
              "This agent is not paired with an account.",
              "Ask your person to pair you on https://regents.sh/account/agents."
            )
        end
      end
    end

    action :account, :map do
      description "Read the paired owner account display name and ENS name together with your pairing ID."

      run fn _input, %{actor: actor} ->
        case Accounts.get_human_account(actor.human_account_id, actor: actor) do
          {:ok, account} ->
            {:ok,
             %{
               account: Map.take(account, [:id, :display_name, :ens_name]),
               pairing_id: actor.pairing_id,
               agent_wallet: actor.wallet_address
             }}

          {:error, _} ->
            refused(
              "unavailable",
              "That could not be reached right now.",
              "Try again in a moment."
            )
        end
      end
    end

    action :claims, :map do
      description "Read the paired owner's verified-wallet historical name claims."

      argument :after, :string, allow_nil?: true, constraints: [min_length: 1, max_length: 2048]

      run fn %{arguments: args}, %{actor: actor} ->
        page = if args[:after], do: [after: args.after], else: []

        case Names.list_my_claims(actor: actor, page: page) do
          {:ok, result} ->
            {:ok,
             %{
               claims: Enum.map(result.results, &Names.present/1),
               next:
                 if(result.more?, do: List.last(result.results).__metadata__.keyset, else: nil)
             }}

          {:error, %{class: :forbidden}} ->
            refused(
              "claims_forbidden",
              "This sign-in can't read these claims.",
              "Retry after verifying pairing."
            )

          {:error, %{class: :invalid}} ->
            refused(
              "invalid_cursor",
              "The after value isn't one this read gave out.",
              "Start again without after, then follow each page's next value."
            )

          {:error, _} ->
            refused(
              "claims_unavailable",
              "Your claims couldn't be read right now.",
              "Try again in a moment."
            )
        end
      end
    end

    action :stake_position, :map do
      description "Read the paired owner's primary-wallet REGENT staking position and claims."

      run fn _input, context ->
        actor = context.actor
        limit_key = context.source_context[:patchbay_limit_key] || actor.wallet_address

        case actor.beneficiary_wallet_address do
          wallet when is_binary(wallet) ->
            case ReadBudget.admit(limit_key) do
              :ok ->
                read_staking_position(wallet)

              {:limited, seconds} ->
                refused(
                  "rate_limited",
                  "Too many requests.",
                  "Wait #{seconds} seconds, then try again."
                )
            end

          _ ->
            refused(
              "wallet_required",
              "This sign-in has no wallet linked.",
              "Link a wallet to this sign-in, then try again."
            )
        end
      end
    end

    action :points, :map do
      description "Read the paired owner's Regent Points summary and leaderboard."

      run fn _input, %{actor: actor} ->
        with {:ok, summary} <- RegentPoints.summary(actor: actor),
             {:ok, %{reading: %{} = board}} <- SharedReading.fetch(Board.key()) do
          phase = Seasons.phase(Seasons.at(DateTime.utc_now()))
          answer = PointsEntries.answer(summary, board, actor.human_account_id, phase)
          note = if Rules.active() == [], do: @points_off, else: nil
          {:ok, if(note, do: Map.put(answer, :note, note), else: answer)}
        else
          _not_read ->
            refused(
              "unavailable",
              "That could not be reached right now.",
              "Try again in a moment."
            )
        end
      end
    end

    action :leave_message, :map do
      description "Leave a private message for the Regents Labs team under a topic."

      argument :topic, :string, allow_nil?: false, constraints: [min_length: 1, max_length: 40]
      argument :body, :string, allow_nil?: false, constraints: [min_length: 1, max_length: 2000]
      argument :reply_to, :string, allow_nil?: true, constraints: [max_length: 200]

      argument :operation_id, :string,
        allow_nil?: false,
        constraints: [min_length: 36, max_length: 36]

      run fn %{arguments: args}, context ->
        client_key = context.source_context[:patchbay_limit_key] || context.actor.wallet_address

        params =
          %{"body" => args.body, "operation_id" => args.operation_id}
          |> then(fn map ->
            if is_binary(args[:reply_to]), do: Map.put(map, "reply_to", args.reply_to), else: map
          end)

        case Messages.agent_leave_message(
               args.topic,
               params,
               actor: context.actor,
               context: %{client_key: client_key}
             ) do
          {:ok, %{receipt: receipt}} ->
            {:ok, %{receipt: receipt}}

          {:error, %Ash.Error.Invalid{errors: errors} = error} ->
            case Enum.find(errors, &is_struct(&1, MessageRefused)) do
              %MessageRefused{code: "idempotency_conflict"} ->
                refused(
                  "idempotency_conflict",
                  "This operation_id was already used for another message.",
                  "Send a new UUID as operation_id for a new message. Keep an operation_id only to retry the same message."
                )

              %MessageRefused{code: code} ->
                refused(
                  code,
                  "The message could not be left.",
                  "Check topic, body, reply_to, and operation_id."
                )

              nil ->
                {:error,
                 Refused.exception(
                   body: %{
                     error: %{
                       code: "invalid_message",
                       message: "The message could not be left.",
                       hint: "Check topic, body, reply_to, and operation_id.",
                       details: FormErrors.details(error)
                     }
                   }
                 )}
            end

          {:error, _} ->
            refused(
              "messages_unavailable",
              "The message could not be left right now.",
              "Try again in a moment."
            )
        end
      end
    end
  end

  policies do
    policy action(:whoami) do
      authorize_if actor_attribute_equals(:role, :agent)
    end

    policy always() do
      authorize_if {RegentAgents.Checks.Paired, repo: Regents.Repo}
    end
  end

  defp pairing_status(nil), do: "not_paired"

  defp pairing_status(%{privy_user_id: privy_user_id}) do
    if AgentAccount.account(privy_user_id), do: "paired", else: "person_not_here"
  end

  defp read_staking_position(wallet) do
    case SnapshotCache.snapshot() do
      nil ->
        refused("staking_unavailable", "Base has not answered yet.", "Try again in a moment.")

      protocol ->
        wallet_facts =
          case Stake.account_for_wallet(wallet) do
            {:ok, facts} -> facts
            {:error, _reason} -> Facts.unavailable_wallet(wallet)
          end

        position = Facts.merge(protocol, wallet_facts)
        {:ok, %{position: position, claims: Stake.available_claims(position)}}
    end
  end

  defp refused(code, message, hint) do
    {:error, Refused.exception(body: %{error: %{code: code, message: message, hint: hint}})}
  end
end
