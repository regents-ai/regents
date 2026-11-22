defmodule Regents.Keyfleet.Capabilities do
  @moduledoc """
  Every tool Keyfleet's pages offer a browser's own agent, read at compile
  time from `priv/keyfleet/tool_manifest.json`, as the table the developer
  documentation shows.
  """

  @manifest_path Application.app_dir(:regents, "priv/keyfleet/tool_manifest.json")
  @external_resource @manifest_path
  @manifest @manifest_path |> File.read!() |> Jason.decode!()
  @tools Map.fetch!(@manifest, "tools")
  @contract_version Map.get(@manifest, "contract_version", "1")
  @guide_version Map.get(@manifest, "guide_version", "1")

  @needs %{
    "none" => "Nothing",
    "siwa" => "Signer",
    "siwa_and_pairing" => "Signer, pairing",
    "siwa_and_pairing_and_product_rights" => "Signer, pairing, Key",
    "wallet" => "Wallet"
  }

  @doc "The contract and guide versions from Keyfleet's tool manifest."
  @spec versions() :: map()
  def versions, do: %{"api_contract" => @contract_version, "agent_guide" => @guide_version}

  @doc "Every tool, in the manifest's order."
  @spec tools() :: [map()]
  def tools, do: @tools

  @doc "Every tool as a Markdown table, after a line saying what its Needs words mean."
  @spec markdown_table() :: String.t()
  def markdown_table do
    """
    Needs: **Signer** is your own SIWA signer; **pairing** your current pairing with a person's account; **Key**, in a fleet, a Key, a shard of one or a pairing with a person who holds one; **Wallet** sign-in and a wallet on your account, on the page named.

    | Tool | Needs | Purpose |
    | --- | --- | --- |
    #{Enum.map_join(@tools, "\n", &"| `#{&1["name"]}` | #{needs(&1)} | #{&1["description"]} |")}\
    """
  end

  # What a tool needs, and for a tool offered on one page only, that page.
  defp needs(%{"scope" => "site", "requires" => requires}), do: Map.fetch!(@needs, requires)

  defp needs(%{"scope" => page, "requires" => requires}),
    do: "#{Map.fetch!(@needs, requires)}, on `#{page}`"
end
