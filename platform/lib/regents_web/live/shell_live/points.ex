defmodule RegentsWeb.ShellLive.Points do
  @moduledoc """
  The Points page: the signed-in account's own points summary, read with the
  account as actor, the board every signed-in reader shares
  (`Regents.Points.Board`) and where Points stands
  (`RegentPoints.Seasons.phase/1`). Awards and corrections from any site, and each
  new reading of the board, are heard only while this page is open, and each one
  reads its part again. The NFT tier the account's wallets hold now is read from
  Base once per page open, never on each award notice, and only while a season
  runs. That read draws on the visitor's `RegentsWeb.ChainReadBudget`; past it,
  the page says the NFTs could not be checked.
  """

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [connected?: 1]

  alias RegentPoints.Seasons
  alias Regents.Actors.Human
  alias Regents.Points.Board
  alias Regents.SharedReading
  alias RegentsWeb.{ChainReadBudget, Read}
  alias RegentsWeb.ShellLive.Identity

  def init(socket),
    do:
      assign(socket,
        points_topic: nil,
        points: %Read{},
        points_board: %Read{},
        points_bonus: %Read{},
        points_phase: :before
      )

  def route(socket, %{route_id: :points}) do
    socket
    |> follow()
    |> assign(points_phase: Seasons.phase(Seasons.at(DateTime.utc_now())))
    |> read()
    |> read_board()
    |> read_bonus()
  end

  def route(socket, _route_spec) do
    socket
    |> unfollow()
    |> Read.clear(:points)
    |> Read.clear(:points_board)
    |> Read.clear(:points_bonus)
  end

  @doc "An award or correction landed for this account."
  def changed(socket), do: read(socket)

  @doc "The board every signed-in reader shares was read again."
  def board_changed(socket), do: read_board(socket)

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

  # The reader's own row is found in the board as the page renders; a place below
  # it comes with their own summary.
  defp read_board(socket) do
    case Identity.human_actor(socket) do
      %Human{} -> assign(socket, points_board: board_read(SharedReading.fetch(Board.key())))
      nil -> Read.clear(socket, :points_board)
    end
  end

  # Loading until the board is first read, an error when that first read failed,
  # and behind while the last read failed.
  defp board_read(:error), do: %Read{state: :loading}
  defp board_read({:ok, %{reading: nil}}), do: %Read{state: :error, error: :not_read}

  defp board_read({:ok, %{reading: board, at: at, degraded?: true}}),
    do: %Read{state: :stale, value: board, read_at: at, error: :not_read}

  defp board_read({:ok, %{reading: board, at: at}}),
    do: %Read{state: :ready, value: board, read_at: at}

  defp read_bonus(%{assigns: %{points_phase: phase}} = socket) when phase != :running,
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
      SharedReading.subscribe(Board.key())
      assign(socket, points_topic: topic)
    else
      _not_followed -> socket
    end
  end

  defp follow(socket), do: socket

  defp unfollow(%{assigns: %{points_topic: nil}} = socket), do: socket

  defp unfollow(socket) do
    Phoenix.PubSub.unsubscribe(Regents.PubSub, socket.assigns.points_topic)
    SharedReading.unsubscribe(Board.key())
    assign(socket, points_topic: nil)
  end
end
