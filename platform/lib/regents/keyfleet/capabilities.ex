defmodule Regents.Keyfleet.Capabilities do
  @moduledoc """
  Every tool Keyfleet's pages offer a browser's own agent, read at compile
  time from `priv/keyfleet/tool_manifest.json`, as `/keyfleet/capabilities.json`,
  the developer documentation table, and hosted MCP tool descriptions use them.
  """

  @manifest_path Application.app_dir(:regents, "priv/keyfleet/tool_manifest.json")
  @external_resource @manifest_path
  @manifest @manifest_path |> File.read!() |> Jason.decode!()
  @tools Map.fetch!(@manifest, "tools")

  @contract_path Application.app_dir(:regents, "priv/keyfleet/public/api-contract.openapiv3.yaml")
  @guide_path Application.app_dir(:regents, "priv/keyfleet/public/skill.md")
  @external_resource @contract_path
  @external_resource @guide_path
  @contract_version ~r/^info:\n(?:  .*\n)*?  version: (\S+)$/m
                    |> Regex.run(File.read!(@contract_path), capture: :all_but_first)
                    |> hd()
  @guide_version ~r/^version: (\S+)$/m
                 |> Regex.run(File.read!(@guide_path), capture: :all_but_first)
                 |> hd()

  @needs %{
    "none" => "Nothing",
    "siwa" => "Signer",
    "siwa_and_pairing" => "Signer, pairing",
    "siwa_and_pairing_and_product_rights" => "Signer, pairing, Key",
    "wallet" => "Wallet"
  }

  @doc "The whole tool manifest."
  @spec manifest() :: map()
  def manifest, do: @manifest

  @doc "The contract and guide versions from Keyfleet's served contract and skill."
  @spec versions() :: %{String.t() => String.t()}
  def versions, do: %{"api_contract" => @contract_version, "agent_guide" => @guide_version}

  @doc "Every tool, in the manifest's order."
  @spec tools() :: [map()]
  def tools, do: @tools

  @doc """
  The request a signed tool sends for `input`, as its browser tool and hosted
  MCP tool build it: `{:ok, method, path, body}`, with route `{names}` filled
  from `input` and the remaining fields as the JSON body.
  """
  @spec request(map(), map()) ::
          {:ok, String.t(), String.t(), map() | nil}
          | {:missing, [String.t()]}
          | {:extra, [String.t()]}
  def request(%{"route" => route}, input) when is_map(input) do
    [method, template] = String.split(route, " ", parts: 2)
    names = ~r/\{(\w+)\}/ |> Regex.scan(template) |> Enum.map(&List.last/1)
    body = Map.drop(input, names)

    case Enum.reject(names, &(is_binary(input[&1]) or is_integer(input[&1]))) do
      [] when method == "GET" and body != %{} ->
        {:extra, Enum.sort(Map.keys(body))}

      [] ->
        path =
          Regex.replace(~r/\{(\w+)\}/, template, fn _whole, name ->
            input[name] |> to_string() |> URI.encode(&URI.char_unreserved?/1)
          end)

        {:ok, method, path, if(method == "GET", do: nil, else: body)}

      missing ->
        {:missing, missing}
    end
  end

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
