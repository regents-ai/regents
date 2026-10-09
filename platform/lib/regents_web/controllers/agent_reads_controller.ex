defmodule RegentsWeb.AgentReadsController do
  @moduledoc "Private reads for a distinct, currently paired SIWA agent."
  use RegentsWeb, :controller

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

    permission =
      RegentCredits.agent_permissions!(actor: actor)
      |> Enum.find(
        &(&1.agent_address == actor.agent_address and &1.pairing_id == actor.pairing_id)
      )

    budget =
      if permission do
        Map.take(permission, [:enabled, :max_per_spend, :daily_limit, :sites])
        |> Map.put(:used_24h, RegentCredits.AgentSpending.spent_today(actor))
        |> Map.put(
          :site_allowed,
          permission.enabled and Regents.Credits.site() in permission.sites
        )
      else
        %{enabled: false, site_allowed: false}
      end

    json(conn, %{pairing_id: actor.pairing_id, spending_grant: budget})
  end

  def history(conn, _params) do
    case pagination(conn.body_params) do
      {:ok, args} ->
        case RegentCredits.history(args, actor: credit_actor(conn)) do
          {:ok, history} -> json(conn, history)
          {:error, %Ash.Error.Invalid{}} -> invalid(conn)
          {:error, _} -> unavailable(conn)
        end

      :error ->
        invalid(conn)
    end
  end

  defp pagination(params) when is_map(params) and map_size(params) == 0, do: {:ok, %{}}

  defp pagination(%{"after" => cursor} = params)
       when map_size(params) == 1 and is_binary(cursor) and byte_size(cursor) in 1..2048,
       do: {:ok, %{after: cursor}}

  defp pagination(_), do: :error

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
      |> put_status(400)
      |> json(%{
        error: %{
          code: "invalid_cursor",
          message: "Send an empty JSON object or only a valid after cursor.",
          hint: "Start with {}, then use the previous page's next value."
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
