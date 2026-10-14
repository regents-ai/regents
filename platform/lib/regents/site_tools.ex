defmodule Regents.SiteTools do
  @moduledoc """
  The browser tools each Regent site offers on its home page, read from the
  site's own published tool list and kept for a day, so a page that shows them
  asks each site at most once a day. A site that could not be read is asked
  again a minute later, never sooner, however often its card is opened.

  Only the five addresses below are ever asked, and a redirect is not followed.

  Patchbay's card lists every tool it publishes, its Agent Offers among them;
  the other sites list the tools of their home page.

  The table lives in this process and is read directly; this process only owns it.
  """

  use GenServer

  @table __MODULE__
  @keep_ms :timer.hours(24)
  @again_ms :timer.minutes(1)

  @sites %{
    "regents" => %{name: "regents.sh", url: "https://regents.sh/capabilities", scopes: :home},
    "patchbay" => %{
      name: "patchbay.help",
      url: "https://patchbay.help/forum/capabilities",
      scopes: :every
    },
    "techtree" => %{name: "techtree.sh", url: "https://techtree.sh/capabilities", scopes: :home},
    "autolaunch" => %{
      name: "autolaunch.sh",
      url: "https://autolaunch.sh/capabilities",
      scopes: :home
    },
    "keyfleet" => %{name: "keyfleet.ai", url: "https://keyfleet.ai/capabilities", scopes: :home}
  }

  @type tool :: %{name: String.t(), title: String.t(), description: String.t()}

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc "The keys of the sites whose tools can be read, in the order the cards show them."
  @spec sites() :: [String.t()]
  def sites, do: ~w(regents patchbay techtree autolaunch keyfleet)

  @doc "A site's address as people know it, such as patchbay.help."
  @spec name(String.t()) :: String.t()
  def name(site), do: Map.fetch!(@sites, site).name

  @doc "The site's tools, from the last day's copy or read from the site now."
  @spec tools(String.t()) :: {:ok, [tool()]} | {:error, :unknown_site | :unreachable}
  def tools(site) do
    case Map.fetch(@sites, site) do
      {:ok, config} -> with :miss <- kept(site), do: read(site, config)
      :error -> {:error, :unknown_site}
    end
  end

  defp kept(site) do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table, site) do
      [{^site, answer, until}] when until > now -> answer
      _none_or_old -> :miss
    end
  end

  defp read(site, config) do
    answer = ask(config)
    keep = if match?({:ok, _tools}, answer), do: @keep_ms, else: @again_ms
    :ets.insert(@table, {site, answer, System.monotonic_time(:millisecond) + keep})
    answer
  end

  defp ask(config) do
    case Req.get(config.url,
           headers: [accept: "application/json"],
           redirect: false,
           retry: false,
           connect_options: [timeout: 3_000],
           receive_timeout: 5_000
         ) do
      {:ok, %Req.Response{status: 200, body: %{"tools" => tools}}} when is_list(tools) ->
        {:ok,
         for(tool when is_map(tool) <- tools, shown?(tool, config.scopes), do: present(tool))}

      _failure ->
        {:error, :unreachable}
    end
  end

  @doc """
  How an agent connects to siwa-server, the one sign-in every Regent site
  shares, in the steps of its guide.
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
            "Your person makes a code on the site's account page. Write it, your name and what you run on to ~/pair.json, pair, then delete the file.",
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

  defp shown?(_tool, :every), do: true
  defp shown?(tool, :home), do: tool["scope"] in ["site", "/"]

  defp present(tool) do
    %{name: tool["name"], title: tool["title"], description: tool["description"]}
  end

  @impl true
  def init(nil) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, nil}
  end
end
