defmodule AshPlatform.PublicContent do
  @moduledoc "Deterministic, non-persistent content for the approved Phase 1 routes."

  @behaviour AshPlatform.ContentProvider

  alias AshPlatform.Content

  @impl true
  def load(route_spec, params) do
    {:ok,
     %Content{
       eyebrow: route_spec.app_display_label,
       status: :preview,
       title: route_spec.page_display_label,
       summary: summary(route_spec.route_id),
       details: details(route_spec.route_id, params)
     }}
  end

  defp summary(:formation), do: "Review the shape of your Regent before setup begins."
  defp summary(:techtree), do: "Explore the five initial research collections."
  defp summary(:autolaunch), do: "Review launches, auctions, and graduated tokens."
  defp summary(:stake), do: "Staking actions are not available in this preview."
  defp summary(:redeem), do: "Redemption actions are not available in this preview."
  defp summary(_), do: "This preview establishes the page and its place in Regent."

  defp details(:techtree_tree, %{"tree_slug" => slug}), do: [{"Dataset", slug}]
  defp details(:techtree_node, %{"node_id" => id}), do: [{"Node", id}]
  defp details(:regent_profile, %{"slug" => slug}), do: [{"Regent", slug}]
  defp details(:autolaunch_auction, %{"auction_id" => id}), do: [{"Auction", id}]
  defp details(:autolaunch_token, %{"token_id" => id}), do: [{"Token", id}]
  defp details(_, _), do: []
end
