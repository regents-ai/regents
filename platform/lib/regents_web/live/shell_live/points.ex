defmodule RegentsWeb.ShellLive.Points do
  @moduledoc """
  The Points page: the signed-in account's own points summary, read with the
  account as actor, and the catalog rules earning now. Awards and corrections
  from any site are heard only while this page is open, and each one reads the
  summary again. The NFT tier the account's wallets hold now is read from Base
  once per page open, never on each award notice, and not at all while nothing
  earns. That read draws on the visitor's `RegentsWeb.ChainReadBudget`; past it,
  the page says the NFTs could not be checked.
  """

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [connected?: 1]

  alias Regents.Actors.Human
  alias RegentsWeb.{ChainReadBudget, Read}
  alias RegentsWeb.ShellLive.Identity

  def init(socket),
    do:
      assign(socket,
        points_topic: nil,
        points: %Read{},
        points_bonus: %Read{},
        points_earning: []
      )

  def route(socket, %{route_id: :points}) do
    socket
    |> follow()
    |> assign(points_earning: RegentPoints.Rules.active())
    |> read()
    |> read_bonus()
  end

  def route(socket, _route_spec),
    do: socket |> unfollow() |> Read.clear(:points) |> Read.clear(:points_bonus)

  @doc "An award or correction landed for this account."
  def changed(socket), do: read(socket)

  defp read(socket) do
    case Identity.human_actor(socket) do
      %Human{} = actor ->
        Read.now(socket, :points, actor.human_account_id, fn ->
          RegentPoints.summary(actor: actor)
        end)

      nil ->
        Read.clear(socket, :points)
    end
  end

  defp read_bonus(%{assigns: %{points_earning: []}} = socket),
    do: Read.clear(socket, :points_bonus)

  defp read_bonus(socket) do
    case Identity.human_actor(socket) do
      %Human{human_account_id: id} ->
        tag = socket.assigns.client_tag
        Read.start(socket, :points_bonus, id, fn -> bonus(id, tag) end)

      nil ->
        Read.clear(socket, :points_bonus)
    end
  end

  defp bonus(id, tag) do
    case ChainReadBudget.admit(tag) do
      :ok -> RegentPoints.Bonus.current(id)
      {:limited, _seconds} -> {:error, :limited}
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
end
