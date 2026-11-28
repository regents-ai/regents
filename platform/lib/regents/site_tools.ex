defmodule Regents.SiteTools do
  @moduledoc """
  Every browser tool each Regents Labs product offers agents, loaded directly
  from the committed canonical `priv/<product>/tool_manifest.json` manifests
  (plus Autolaunch's split feature tool manifests) shipped in this single site
  so every product's tool list and capabilities endpoint answer immediately
  without remote HTTP calls.
  """

  @autolaunch_extra_manifests [
    "priv/autolaunch/covered_calls_tools.json",
    "priv/autolaunch/exposure_tools.json",
    "priv/autolaunch/earn_tools.json",
    "priv/autolaunch/agent_bids_tools.json",
    "priv/autolaunch/agent_robinhood_bids_tools.json",
    "priv/autolaunch/agent_launches_tools.json",
    "priv/autolaunch/agent_finish_tools.json",
    "priv/autolaunch/agent_stake_tools.json",
    "priv/autolaunch/agent_swap_tools.json",
    "priv/autolaunch/agent_payment_tools.json"
  ]

  @sites %{
    "regents" => %{name: "regents.sh", manifest: "priv/tool_manifest.json", extras: []},
    "patchbay" => %{
      name: "regents.sh/patchbay",
      manifest: "priv/patchbay/tool_manifest.json",
      extras: []
    },
    "techtree" => %{
      name: "regents.sh/techtree",
      manifest: "priv/techtree/tool_manifest.json",
      extras: []
    },
    "autolaunch" => %{
      name: "regents.sh/autolaunch",
      manifest: "priv/autolaunch/tool_manifest.json",
      extras: @autolaunch_extra_manifests
    },
    "keyfleet" => %{
      name: "regents.sh/keyfleet",
      manifest: "priv/keyfleet/tool_manifest.json",
      extras: []
    }
  }

  for %{manifest: path, extras: extras} <- Map.values(@sites),
      file <- [path | extras] do
    @external_resource Application.app_dir(:regents, file)
  end

  @manifests Map.new(@sites, fn {site, %{manifest: path, extras: extras}} ->
               base = :regents |> Application.app_dir(path) |> File.read!() |> Jason.decode!()

               extra_tools =
                 Enum.flat_map(extras, fn extra_path ->
                   :regents
                   |> Application.app_dir(extra_path)
                   |> File.read!()
                   |> Jason.decode!()
                   |> Map.get("tools", [])
                 end)

               merged_tools =
                 (Map.get(base, "tools", []) ++ extra_tools)
                 |> Enum.uniq_by(& &1["name"])

               {site, Map.put(base, "tools", merged_tools)}
             end)

  @type tool :: %{name: String.t(), title: String.t() | nil, description: String.t() | nil}

  @doc "The keys of the products whose tools can be read, in the order they are listed."
  @spec sites() :: [String.t()]
  def sites, do: ~w(regents patchbay autolaunch techtree keyfleet)

  @doc "A product's address as people know it, such as regents.sh/patchbay."
  @spec name(String.t()) :: String.t()
  def name(site), do: Map.fetch!(@sites, site).name

  @doc "Relative priv path to a product's canonical `tool_manifest.json`."
  @spec manifest_path(String.t()) :: {:ok, String.t()} | :error
  def manifest_path(site) do
    case Map.fetch(@sites, site) do
      {:ok, %{manifest: manifest}} -> {:ok, manifest}
      :error -> :error
    end
  end

  @doc "The full decoded canonical `priv/<product>/tool_manifest.json` map (including split feature manifests)."
  @spec manifest(String.t()) :: {:ok, map()} | {:error, :unknown_site | :unreachable}
  def manifest(site) do
    case Map.fetch(@manifests, site) do
      {:ok, manifest} -> {:ok, manifest}
      :error -> {:error, :unknown_site}
    end
  end

  @doc "The product's tools, loaded from its committed manifest."
  @spec tools(String.t()) :: {:ok, [tool()]} | {:error, :unknown_site | :unreachable}
  def tools(site) do
    case manifest(site) do
      {:ok, %{"tools" => tools}} when is_list(tools) ->
        {:ok, for(tool when is_map(tool) <- tools, do: present(tool))}

      {:error, _reason} = error ->
        error

      _malformed ->
        {:error, :unreachable}
    end
  end

  @doc "Every product's tools as `tools/1` answers them, in the order of `sites/0`."
  @spec every_site() :: [{String.t(), {:ok, [tool()]} | {:error, :unreachable}}]
  def every_site do
    Enum.map(sites(), &{&1, tools(&1)})
  end

  @doc """
  How an agent connects to siwa-server, the one sign-in every Regents Labs
  product shares, in the steps of its guide.
  """
  @spec connection_help() :: map()
  def connection_help do
    %{
      guide: "https://siwa.regents.sh/skill.md",
      steps: [
        %{
          title: "Get the client",
          copy: "One file, run with uv. Node users take siwa-agent.mjs instead.",
          command: "curl -fsSO https://siwa.regents.sh/agent/siwa_agent.py"
        },
        %{
          title: "Choose how you sign",
          copy:
            "Make a key the client keeps, or give it your own wallet's address and the command that signs a message.",
          command: "uv run siwa_agent.py keygen"
        },
        %{
          title: "Pair with your person",
          copy:
            "Your person makes a code with Pair New Agent on the site's Agents page. Write it, your name and what you run on to ~/pair.json, pair, then delete the file.",
          command: "uv run siwa_agent.py pair https://regents.sh < ~/pair.json"
        },
        %{
          title: "Check who you are",
          copy: "Shows your address and where you are paired.",
          command: "uv run siwa_agent.py request GET https://regents.sh/api/agents/v1/whoami"
        }
      ]
    }
  end

  defp present(tool) do
    %{name: tool["name"], title: tool["title"], description: tool["description"]}
  end
end
