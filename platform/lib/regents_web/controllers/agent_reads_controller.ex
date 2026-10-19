defmodule RegentsWeb.AgentReadsController do
  @moduledoc "Private reads for a distinct, currently paired SIWA agent."
  use RegentsWeb, :controller

  # The spending grant fields the published contract names.
  @published_budget [:enabled, :site_allowed, :max_per_spend, :daily_limit, :sites, :used_24h]

  def account(conn, _params) do
    actor = conn.assigns.actor

    case Regents.Accounts.get_human_account(actor.human_account_id, actor: actor) do
      {:ok, account} ->
        json(conn, %{
          account: Map.take(account, [:id, :display_name, :ens_name]),
          pairing_id: actor.pairing_id,
          agent_wallet: actor.wallet_address
        })

      {:error, _} ->
        unavailable(conn)
    end
  end

  def balance(conn, _params),
    do:
      json(conn, %{
        credits: RegentCredits.balance(conn.assigns.actor.privy_user_id),
        pairing_id: conn.assigns.actor.pairing_id
      })

  def points(conn, _params) do
    case RegentPoints.summary(actor: conn.assigns.actor) do
      {:ok, summary} ->
        entries =
          Enum.map(
            summary.entries,
            &Map.take(&1, [
              :id,
              :rule_id,
              :rule_version,
              :source_app,
              :actor_kind,
              :actor_id,
              :points_micro_delta,
              :earned_at,
              :reason_code
            ])
          )

        result =
          Map.take(summary, [:balance_micro, :earned_today_micro, :pending, :allowances, :more?])

        json(conn, Map.put(result, :entries, entries))

      {:error, _} ->
        unavailable(conn)
    end
  end

  def budget(conn, _params) do
    actor = credit_actor(conn)

    case RegentCredits.agent_budget(actor: actor) do
      {:ok, budget} ->
        json(conn, %{
          pairing_id: actor.pairing_id,
          spending_grant: Map.take(budget, @published_budget)
        })

      {:error, _} ->
        unavailable(conn)
    end
  end

  def history(conn, _params) do
    with {:ok, args} <- pagination(conn.body_params),
         {:ok, history} <- RegentCredits.history(args, actor: credit_actor(conn)) do
      json(conn, %{
        entries: history.entries,
        pagination: %{has_more: history.more?, next_cursor: history.next}
      })
    else
      :error -> invalid(conn)
      {:error, error} -> if cursor_error?(error), do: invalid(conn), else: unavailable(conn)
    end
  end

  defp pagination(params) when is_map(params) and map_size(params) == 0, do: {:ok, %{}}

  defp pagination(%{"after" => cursor} = params)
       when map_size(params) == 1 and is_binary(cursor) and byte_size(cursor) in 1..2048,
       do: {:ok, %{after: cursor}}

  defp pagination(_), do: :error

  defp cursor_error?(%Ash.Error.Action.InvalidArgument{field: :after}), do: true
  defp cursor_error?(%Ash.Error.Page.InvalidKeyset{}), do: true

  defp cursor_error?(%Ash.Error.Invalid{errors: [_ | _] = errors}),
    do: Enum.all?(errors, &cursor_error?/1)

  defp cursor_error?(_error), do: false

  defp credit_actor(conn) do
    actor = conn.assigns.actor

    RegentCredits.Actor.agent(
      actor.privy_user_id,
      actor.wallet_address,
      Regents.Credits.site(),
      actor.pairing_id
    )
  end

  defp invalid(conn),
    do:
      conn
      |> put_status(422)
      |> json(%{
        error: %{
          code: "invalid_cursor",
          message: "That history cursor is invalid.",
          hint:
            "Send after as the previous page's pagination.next_cursor, unchanged, or omit it for the newest entries."
        }
      })

  defp unavailable(conn),
    do:
      conn
      |> put_status(503)
      |> json(%{
        error: %{
          code: "unavailable",
          message: "The private read could not be completed.",
          hint: "Try again in a moment with fresh proof."
        }
      })
end
