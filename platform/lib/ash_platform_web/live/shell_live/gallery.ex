defmodule AshPlatformWeb.ShellLive.Gallery do
  @moduledoc """
  The gallery's "My passes" filter. It reads the signed-in account's own
  wallets once; after that the toggle only shows or hides what is already on
  the page. A lookup that failed is tried again the next time the filter is
  switched on. What it found stays with the page while the same account is
  signed in, so leaving the gallery and coming back shows it again.
  """

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [start_async: 3]

  alias AshPlatform.OpenSea
  alias AshPlatformWeb.ShellLive.{Identity, OpenSeaBudget}

  def init(socket), do: assign(socket, gallery_mine: false, gallery_owned: idle())

  def toggle(
        %{assigns: %{route_spec: %{route_id: :redeem_gallery}, gallery_mine: false}} = socket
      ) do
    case Identity.current_account(socket.assigns.access_context) do
      nil -> socket
      account -> socket |> assign(gallery_mine: true) |> start_lookup(account)
    end
  end

  def toggle(socket), do: assign(socket, gallery_mine: false)

  @doc """
  A lookup answers only for the account it was made for. Signing out or
  switching account ends this process, but a
  session can also end quietly under it, and then the passes it found are
  dropped.
  """
  def settle(socket, {:gallery_owned, account_id}, result) do
    case {Identity.current_account(socket.assigns.access_context), result} do
      {%{id: ^account_id}, {:ok, {:ok, ids}}} ->
        assign(socket, gallery_owned: %{status: :ready, ids: ids})

      {%{id: ^account_id}, _failed} ->
        assign(socket, gallery_owned: %{status: :unavailable, ids: []})

      _session_ended ->
        assign(socket, gallery_mine: false, gallery_owned: idle())
    end
  end

  defp start_lookup(%{assigns: %{gallery_owned: %{status: status}}} = socket, account)
       when status in [:idle, :unavailable] do
    case OpenSeaBudget.claim(socket) do
      {:limited, socket} ->
        assign(socket, gallery_owned: %{status: :unavailable, ids: []})

      {:ok, socket} ->
        wallets = Identity.account_wallets(account)

        socket
        |> assign(gallery_owned: %{status: :loading, ids: []})
        |> start_async({:gallery_owned, account.id}, fn -> owned_pass_ids(wallets) end)
    end
  end

  defp start_lookup(socket, _account), do: socket

  defp owned_pass_ids(wallets) do
    wallets
    |> Enum.reduce_while({:ok, []}, fn wallet, {:ok, ids} ->
      case OpenSea.fetch_owned_collectibles(wallet) do
        {:ok, %{regents_club: club}} -> {:cont, {:ok, Enum.map(club, & &1.token_id) ++ ids}}
        _unavailable -> {:halt, :unavailable}
      end
    end)
    |> case do
      {:ok, ids} -> {:ok, ids |> Enum.uniq() |> Enum.sort()}
      :unavailable -> :unavailable
    end
  end

  defp idle, do: %{status: :idle, ids: []}
end
