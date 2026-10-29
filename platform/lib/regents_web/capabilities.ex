defmodule RegentsWeb.Capabilities do
  @moduledoc """
  What a paired agent may do on this site, in its person's words, which the
  Account page shows. Each browser tool an agent signs for in
  `priv/tool_manifest.json` has its words here, or `nil` for a tool about the
  agent itself; the two are checked against each other when this module
  compiles, so a new signed tool cannot reach agents without saying what it lets
  them do.
  """

  path = Application.app_dir(:regents, "priv/tool_manifest.json")
  @external_resource path

  @words %{
    "regents_stake_position" => "Read your staking position",
    "regents_claims" => "Read your name claims",
    "regents_name_check" => "Check a name and your free claims left",
    "regents_name_claim" => "Claim a free name for you",
    "regents_agent_whoami" => nil,
    "regents_agent_status" => "Check in with you",
    "regents_account" => "Read your display name and ENS name",
    "regents_credits_balance" => "Read your Credits balance",
    "regents_credits_history" => "Read your Credits history",
    "regents_credits_budget" => "Read what it may spend of your Credits",
    "regents_points_summary" => "Read your Points"
  }

  signed =
    for %{"authentication" => "siwa_per_request", "name" => name} <-
          path |> File.read!() |> Jason.decode!() |> Map.fetch!("tools"),
        do: name

  unless MapSet.new(signed) == MapSet.new(Map.keys(@words)),
    do: raise("RegentsWeb.Capabilities must give words for every signed tool, and only those")

  @may signed |> Enum.map(&Map.fetch!(@words, &1)) |> Enum.reject(&is_nil/1) |> Enum.uniq()

  @doc "What a paired agent may do on this site, in its person's words, a line each."
  @spec may() :: [String.t()]
  def may, do: @may
end
