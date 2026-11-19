defmodule RegentPoints.Bonus do
  @moduledoc """
  The approved NFT tiers. Current holdings are a preview; only the fixed snapshot
  at the end of each 30-day period determines the confirmed bonus.
  """
  alias RegentPoints.{Nfts, Snapshot, Store}
  @tiers [{7, 75}, {3, 45}, {1, 20}]
  def tiers, do: @tiers
  def allowed_percentages, do: [0 | @tiers |> Enum.map(&elem(&1, 1)) |> Enum.sort()]

  def percent(count) do
    case Enum.find(@tiers, fn {minimum, _} -> count >= minimum end) do
      {_, percent} -> percent
      nil -> 0
    end
  end

  @doc "The tier the account's linked wallets hold now, read from Base and never saved."
  def current(account_id) do
    wallets = account_id |> Store.human() |> Store.wallets()

    with {:ok, holdings} <- Nfts.latest(wallets) do
      {:ok, %{nft_count: holdings.count, percent: percent(holdings.count), block: holdings.block}}
    end
  end

  @doc "The immutable period-end tier, including historical wallet attribution."
  def at_snapshot(account_id, snapshot) do
    block = %{number: snapshot.block_number, hash: snapshot.block_hash}

    with {:ok, wallets} <- Snapshot.wallets(account_id, snapshot),
         {:ok, holdings} <- Nfts.at_block(wallets, block) do
      {:ok, %{nft_count: holdings.count, percent: percent(holdings.count), block: holdings.block}}
    end
  end
end
