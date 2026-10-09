defmodule RegentsWeb.ShellLive.Points do
  @moduledoc """
  The Points page: the signed-in account's own points summary, read with the
  account as actor, and the catalog rules earning now. Awards and corrections
  from any site are heard only while this page is open, and each one reads the
  summary again. A refresh that fails keeps the last summary on screen as
  stale; a first read that fails is an error, never zero. The NFT tier the
  account's wallets hold now is read from Base once per page open and never saved.
  """

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [connected?: 1, start_async: 3]

  alias RegentsWeb.ShellLive.Identity

  def init(socket),
    do:
      assign(socket, points_topic: nil, points: idle(), points_bonus: idle(), points_earning: [])

  def route(socket, %{route_id: :account_points}) do
    socket
    |> follow()
    |> assign(points_earning: RegentPoints.Rules.active())
    |> read()
    |> read_bonus()
  end

  def route(socket, _route_spec),
    do: socket |> unfollow() |> assign(points: idle(), points_bonus: idle())

  @doc "An award or correction landed for this account."
  def changed(socket), do: read(socket)

  @doc """
  A summary answers only for the account it was read for, and only while the
  Points page is open. A newer read for the same account replaces an older one
  that is still running, whose answer LiveView then drops.
  """
  def settle(%{assigns: %{route_spec: %{route_id: :account_points}}} = socket, name, result),
    do: landed(socket, name, result)

  def settle(socket, _name, _result), do: socket

  defp landed(socket, {:points, account_id}, result) do
    case {Identity.current_account(socket.assigns.access_context), result} do
      {%{id: ^account_id}, {:ok, {:ok, summary}}} ->
        assign(socket, points: %{state: :ready, value: summary})

      {%{id: ^account_id}, _failed} ->
        assign(socket, points: failed(socket.assigns.points))

      _session_ended ->
        assign(socket, points: idle())
    end
  end

  defp landed(socket, {:points_bonus, account_id}, result) do
    case {Identity.current_account(socket.assigns.access_context), result} do
      {%{id: ^account_id}, {:ok, {:ok, tier}}} ->
        assign(socket, points_bonus: %{state: :ready, value: tier})

      {%{id: ^account_id}, _failed} ->
        assign(socket, points_bonus: %{state: :error, value: nil})

      _session_ended ->
        assign(socket, points_bonus: idle())
    end
  end

  defp read(socket) do
    case Identity.human_actor(socket) do
      nil ->
        assign(socket, points: idle())

      actor ->
        socket
        |> assign(points: %{socket.assigns.points | state: :loading})
        |> start_async({:points, actor.human_account_id}, fn ->
          RegentPoints.summary(actor: actor)
        end)
    end
  end

  defp read_bonus(socket) do
    case Identity.human_actor(socket) do
      nil ->
        assign(socket, points_bonus: idle())

      %{human_account_id: id} ->
        socket
        |> assign(points_bonus: %{state: :loading, value: nil})
        |> start_async({:points_bonus, id}, fn -> RegentPoints.Bonus.current(id) end)
    end
  end

  defp follow(%{assigns: %{points_topic: nil}} = socket) do
    with true <- connected?(socket),
         %{id: id} <- Identity.current_account(socket.assigns.access_context) do
      topic = "points:#{id}"
      Phoenix.PubSub.subscribe(Regents.PubSub, topic)
      assign(socket, points_topic: topic)
    else
      _not_followed -> socket
    end
  end

  defp follow(socket), do: socket

  defp unfollow(%{assigns: %{points_topic: nil}} = socket), do: socket

  defp unfollow(socket) do
    Phoenix.PubSub.unsubscribe(Regents.PubSub, socket.assigns.points_topic)
    assign(socket, points_topic: nil)
  end

  defp failed(%{value: nil}), do: %{state: :error, value: nil}
  defp failed(points), do: %{points | state: :stale}

  defp idle, do: %{state: :idle, value: nil}
end
