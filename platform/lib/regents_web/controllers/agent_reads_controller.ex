defmodule RegentsWeb.AgentReadsController do
  @moduledoc "Private reads for a distinct, currently paired SIWA agent."
  use RegentsWeb, :controller

  alias RegentPoints.Rules
  alias RegentsWeb.PointsEntries

  @points_off "Earning Points is off on this site."
  @spending_closed "Agent spending isn't open yet. Your person can do this themselves."
  @spending_ask "Your person can allow you to spend Credits on this site on their Regents account at regents.sh/account."

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

  # What the agent may spend, and the note, both come from the agent's budget
  # (`RegentCredits.agent_budget/1`): its grant, and whether a grant can be made.
  def balances(conn, _params) do
    actor = credit_actor(conn)

    case RegentCredits.agent_budget(actor: actor) do
      {:ok, budget} ->
        answer = %{credits: RegentCredits.balance(actor.privy_user_id), spending_grant: budget}
        json(conn, with_note(answer, spending_note(budget)))

      {:error, _} ->
        unavailable(conn)
    end
  end

  defp spending_note(%{site_allowed: true}), do: nil
  defp spending_note(%{grant_approvals_available: false}), do: @spending_closed
  defp spending_note(%{grant_approvals_available: true}), do: @spending_ask

  def credits_history(%{body_params: %{"after" => cursor}} = conn, _params)
      when not is_binary(cursor),
      do: invalid(conn)

  def credits_history(conn, _params) do
    args =
      case conn.body_params do
        %{"after" => cursor} when is_binary(cursor) -> %{after: cursor}
        _ -> %{}
      end

    case RegentCredits.history(args, actor: credit_actor(conn)) do
      {:ok, history} ->
        json(conn, %{
          entries: history.entries,
          pagination: %{has_more: history.more?, next_cursor: history.next}
        })

      {:error, error} ->
        if cursor_error?(error), do: invalid(conn), else: unavailable(conn)
    end
  end

  defp cursor_error?(%Ash.Error.Action.InvalidArgument{field: :after}), do: true
  defp cursor_error?(%Ash.Error.Page.InvalidKeyset{}), do: true

  defp cursor_error?(%Ash.Error.Invalid{errors: [_ | _] = errors}),
    do: Enum.all?(errors, &cursor_error?/1)

  defp cursor_error?(_error), do: false

  # Points as decimal text, the same figures the Points page shows.
  def points(conn, _params) do
    case RegentPoints.summary(actor: conn.assigns.actor) do
      {:ok, summary} ->
        json(conn, with_note(PointsEntries.answer(summary), points_note(Rules.active())))

      {:error, _} ->
        unavailable(conn)
    end
  end

  defp points_note([]), do: @points_off
  defp points_note(_earning), do: nil

  defp with_note(answer, nil), do: answer
  defp with_note(answer, note), do: Map.put(answer, :note, note)

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
          message: "That cursor is invalid.",
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
          message: "That could not be reached right now.",
          hint: "Try again in a moment."
        }
      })
end
