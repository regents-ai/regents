defmodule AshPlatformWeb.StakingPositionController do
  @moduledoc """
  What the Stake page shows for the signed-in person's wallet: the shared
  contract reading beside a fresh reading of their own wallet, merged the way
  the page merges them.
  """
  use AshPlatformWeb, :controller

  alias AshPlatform.Staking
  alias AshPlatform.Staking.Facts
  alias AshPlatform.Staking.SnapshotCache
  alias AshPlatformWeb.PrivyPair

  def show(conn, params) do
    conn =
      conn
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_header("vary", "Authorization, Privy-Id-Token")

    case {PrivyPair.verify(conn), params} do
      {{:ok, %{wallet_address: wallet}}, params}
      when is_binary(wallet) and map_size(params) == 0 ->
        position(conn, wallet)

      {{:ok, _actor}, params} when map_size(params) > 0 ->
        error(conn, 400, "invalid_query", "This read takes no query parameters.")

      {{:ok, _actor}, _params} ->
        error(conn, 409, "wallet_required", "Link a wallet to this sign-in first.")

      {{:error, :unconfigured}, _params} ->
        error(conn, 503, "staking_unconfigured", "Sign-in checks are not set up here.")

      {{:error, :unauthenticated}, _params} ->
        error(conn, 401, "authentication_required", "Send the Privy access and identity tokens.")
    end
  end

  # A wallet reading that fails leaves the wallet's figures unavailable beside
  # the contract reading, exactly as the page shows it.
  defp position(conn, wallet) do
    case SnapshotCache.snapshot() do
      nil ->
        error(conn, 503, "staking_unavailable", "Base has not answered yet. Try again shortly.")

      protocol ->
        wallet_facts =
          case Staking.account_for_wallet(wallet) do
            {:ok, facts} -> facts
            {:error, _reason} -> Facts.unavailable_wallet(wallet)
          end

        json(conn, %{position: Facts.merge(protocol, wallet_facts)})
    end
  end

  defp error(conn, status, code, message),
    do: conn |> put_status(status) |> json(%{error: %{code: code, message: message}})
end
