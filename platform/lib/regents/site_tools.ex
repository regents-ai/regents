defmodule Regents.SiteTools do
  @moduledoc """
  Every browser tool each Regents Labs product offers agents, loaded directly
  from the committed tool manifests shipped in this single site so every
  product's tool list answers immediately without remote HTTP calls.
  """

  use GenServer

  @sites %{
    "regents" => %{name: "regents.sh", manifest: "priv/tool_manifest.json"},
    "patchbay" => %{name: "regents.sh/patchbay", manifest: "priv/patchbay/tool_manifest.json"},
    "techtree" => %{name: "regents.sh/techtree", manifest: "priv/techtree/tool_manifest.json"},
    "autolaunch" => %{
      name: "regents.sh/autolaunch",
      manifest: "priv/autolaunch/tool_manifest.json"
    },
    "keyfleet" => %{name: "regents.sh/keyfleet", manifest: "priv/keyfleet/tool_manifest.json"}
  }

  @type tool :: %{name: String.t(), title: String.t() | nil, description: String.t() | nil}

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc "The keys of the products whose tools can be read, in the order they are listed."
  @spec sites() :: [String.t()]
  def sites, do: ~w(regents patchbay autolaunch techtree keyfleet)

  @doc "A product's address as people know it, such as regents.sh/patchbay."
  @spec name(String.t()) :: String.t()
  def name(site), do: Map.fetch!(@sites, site).name

  @doc "The product's tools, loaded from its committed manifest."
  @spec tools(String.t()) :: {:ok, [tool()]} | {:error, :unknown_site | :unreachable}
  def tools(site) do
    case Map.fetch(@sites, site) do
      {:ok, %{manifest: manifest}} -> read_manifest(manifest)
      :error -> {:error, :unknown_site}
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

  defp read_manifest(relative_path) do
    path = Application.app_dir(:regents, relative_path)

    with {:ok, raw} <- File.read(path),
         {:ok, %{"tools" => tools}} when is_list(tools) <- Jason.decode(raw) do
      {:ok, for(tool when is_map(tool) <- tools, do: present(tool))}
    else
      _failure -> {:error, :unreachable}
    end
  end

  defp present(tool) do
    %{name: tool["name"], title: tool["title"], description: tool["description"]}
  end

  @impl true
  def init(nil), do: {:ok, %{}}
end
