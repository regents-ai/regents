defmodule RegentsWeb.StakingPositionController do
  @moduledoc """
  What the Stake page shows for the signed-in person's wallet: the shared
  contract reading beside a fresh reading of their own wallet, merged the way
  the page merges them.
  """
  use RegentsWeb, :controller

  alias Regents.Staking
  alias Regents.Staking.Facts
  alias Regents.Staking.SnapshotCache
  alias RegentsWeb.{ChainReadBudget, ClientAddress, PrivyPair}

  def show(conn, params) do
    conn =
      conn
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_header("vary", "Authorization, Privy-Id-Token")

    case {PrivyPair.verify(conn), params} do
      {{:ok, %{wallet_address: wallet}}, params}
      when is_binary(wallet) and map_size(params) == 0 ->
        admit(conn, wallet)

      {{:ok, _actor}, params} when map_size(params) > 0 ->
        error(conn, "invalid_query")

      {{:ok, _actor}, _params} ->
        error(conn, "wallet_required")

      {{:error, :unconfigured}, _params} ->
        error(conn, "staking_unconfigured")

      {{:error, :unauthenticated}, _params} ->
        error(conn, "authentication_required")
    end
  end

  # Each reading of Base draws on the caller's address budget, shared with the
  # pages.
  defp admit(conn, wallet) do
    case ChainReadBudget.admit(ClientAddress.tag(conn)) do
      :ok ->
        position(conn, wallet)

      {:limited, seconds} ->
        conn |> put_resp_header("retry-after", "#{seconds}") |> error("rate_limited")
    end
  end

  # A wallet reading that fails leaves the wallet's figures unavailable beside
  # the contract reading, exactly as the page shows it.
  defp position(conn, wallet) do
    case SnapshotCache.snapshot() do
      nil ->
        error(conn, "staking_unavailable")

      protocol ->
        wallet_facts =
          case Staking.account_for_wallet(wallet) do
            {:ok, facts} -> facts
            {:error, _reason} -> Facts.unavailable_wallet(wallet)
          end

        json(conn, %{position: Facts.merge(protocol, wallet_facts)})
    end
  end

  # Every refusal: a code for programs, a message and a hint for people.
  @errors %{
    "invalid_query" =>
      {400, "This read takes no query parameters.",
       "Send the request again without a query string."},
    "wallet_required" =>
      {409, "This sign-in has no wallet linked.",
       "Link a wallet to this sign-in, then try again."},
    "staking_unconfigured" => {503, "Sign-in checks are not set up here.", "Try again later."},
    "authentication_required" =>
      {401, "Sign in to read your stake.",
       "Send the Privy access token as a Bearer token and the identity token in privy-id-token, both from the same sign-in."},
    "staking_unavailable" => {503, "Base has not answered yet.", "Try again in a moment."},
    "rate_limited" =>
      {429, "Too many requests.", "Wait the number of seconds in Retry-After, then try again."}
  }

  defp error(conn, code) do
    {status, message, hint} = Map.fetch!(@errors, code)
    conn |> put_status(status) |> json(%{error: %{code: code, message: message, hint: hint}})
  end
end
