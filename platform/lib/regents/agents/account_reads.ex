defmodule Regents.Agents.AccountReads do
  @moduledoc """
  A paired agent's private reads of its person's account: the account, Credits
  and Points. Each is one action, which the agent API
  (`RegentsWeb.AgentReadsController`) and the hosted MCP server both run, and
  each answers the JSON body the API sends. Only a paired agent
  (`Regents.Actors.Agent`) runs them, whether it signs its own requests or is a
  connected app working here as its paired identity. A read that could not be
  done is refused with the API's code (`Regents.Agents.AccountReads.Refused`).
  """

  use Ash.Resource,
    domain: Regents.Agents,
    authorizers: [Ash.Policy.Authorizer]

  alias Regents.Agents.AccountReads.Refused

  # The spending grant fields the published contract names.
  @published_budget [:enabled, :site_allowed, :max_per_spend, :daily_limit, :sites, :used_24h]

  @point_entry [
    :id,
    :rule_id,
    :rule_version,
    :source_app,
    :actor_kind,
    :actor_id,
    :points_micro_delta,
    :earned_at,
    :reason_code
  ]

  actions do
    action :account, :map do
      description "Reads the paired account's display name and ENS name, with the pairing."

      run fn _input, %{actor: actor} ->
        case Regents.Accounts.get_human_account(actor.human_account_id, actor: actor) do
          {:ok, account} ->
            {:ok,
             %{
               account: Map.take(account, [:id, :display_name, :ens_name]),
               pairing_id: actor.pairing_id,
               agent_wallet: actor.wallet_address
             }}

          {:error, _} ->
            unavailable()
        end
      end
    end

    action :credits_balance, :map do
      description "Reads the paired account's Credits balance."

      run fn _input, %{actor: actor} ->
        {:ok,
         %{credits: RegentCredits.balance(actor.privy_user_id), pairing_id: actor.pairing_id}}
      end
    end

    action :credits_budget, :map do
      description "Reads what this pairing may spend of the account's Credits."

      run fn _input, %{actor: actor} ->
        credit_actor = credit_actor(actor)

        case RegentCredits.agent_budget(actor: credit_actor) do
          {:ok, budget} ->
            {:ok,
             %{
               pairing_id: credit_actor.pairing_id,
               spending_grant: Map.take(budget, @published_budget)
             }}

          {:error, _} ->
            unavailable()
        end
      end
    end

    action :credits_history, :map do
      description "Reads the paired account's Credits history, newest first."

      argument :after, :string,
        constraints: [min_length: 1, max_length: 2048, trim?: false, allow_empty?: true],
        description:
          "The previous page's pagination.next_cursor unchanged. Omit for the first page or when the cursor is null."

      run fn input, %{actor: actor} ->
        page = if cursor = input.arguments[:after], do: %{after: cursor}, else: %{}

        case RegentCredits.history(page, actor: credit_actor(actor)) do
          {:ok, history} ->
            {:ok,
             %{
               entries: history.entries,
               pagination: %{has_more: history.more?, next_cursor: history.next}
             }}

          {:error, error} ->
            if cursor_error?(error),
              do: {:error, Refused.exception(code: "invalid_cursor")},
              else: unavailable()
        end
      end
    end

    action :points_summary, :map do
      description "Reads the paired account's Points: balance, recent entries and allowances."

      run fn _input, %{actor: actor} ->
        case RegentPoints.summary(actor: actor) do
          {:ok, summary} ->
            {:ok,
             summary
             |> Map.take([:balance_micro, :earned_today_micro, :pending, :allowances, :more?])
             |> Map.put(:entries, Enum.map(summary.entries, &Map.take(&1, @point_entry)))}

          {:error, _} ->
            unavailable()
        end
      end
    end
  end

  policies do
    policy always() do
      authorize_if actor_attribute_equals(:role, :agent)
    end
  end

  defp unavailable, do: {:error, Refused.exception(code: "unavailable")}

  defp credit_actor(actor),
    do:
      RegentCredits.Actor.agent(
        actor.privy_user_id,
        actor.wallet_address,
        Regents.Credits.site(),
        actor.pairing_id
      )

  defp cursor_error?(%Ash.Error.Action.InvalidArgument{field: :after}), do: true
  defp cursor_error?(%Ash.Error.Page.InvalidKeyset{}), do: true

  defp cursor_error?(%Ash.Error.Invalid{errors: [_ | _] = errors}),
    do: Enum.all?(errors, &cursor_error?/1)

  defp cursor_error?(_error), do: false
end
