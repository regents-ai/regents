defmodule RegentsWeb.Keyfleet.AgentCompatibility do
  @moduledoc """
  Which agent runtimes have passed Keyfleet's compatibility checks, and through
  which connection: the page at `/keyfleet/agents/compatibility` and the Verified
  line on the page at `/keyfleet/agents/SLUG` of each runtime that passed.

  The checks, the connections and the runtimes are
  `priv/keyfleet/agent_compatibility.yml`, which also describes a run. Each run
  is one Markdown file in `priv/keyfleet/agent_runs/`. A cell is the newest
  run's result for that runtime and connection, and NOT RUN without one. A
  runtime is Verified through a connection only when that newest run is
  witnessed and every check passed or is not supported there; any other runtime
  carries no status. A run that doesn't follow the file's rules stops the
  build. Nothing here reads the database.
  """

  alias RegentsWeb.Keyfleet.AgentGuides

  @suite_path Application.app_dir(:regents, "priv/keyfleet/agent_compatibility.yml")
  @external_resource @suite_path
  @suite @suite_path |> File.read!() |> YamlElixir.read_from_string!()

  @runs_directory Application.app_dir(:regents, "priv/keyfleet/agent_runs")
  @run_files @runs_directory |> Path.join("*.md") |> Path.wildcard() |> Enum.sort()
  for file <- @run_files, do: @external_resource(file)

  @runtimes @suite["runtimes"]
  @interfaces @suite["interfaces"]
  @checks @suite["checks"]
  @scenarios @suite["scenarios"]
  @version @suite["version"]
  @date @suite["date"]
  @outcomes ["PASS", "FAIL", "BLOCKED", "NOT SUPPORTED", "NOT RUN"]

  runs =
    for file <- @run_files do
      ["", front, evidence] = file |> File.read!() |> String.split("---\n", parts: 3)
      run = YamlElixir.read_from_string!(front)
      results = run["results"]
      together? = match?([_, _ | _], run["runtimes"])
      steps = Enum.map(if(together?, do: @scenarios, else: @checks), & &1["id"])
      witnessed? = run["witnessed"] == true

      text? = &(is_nil(&1) or is_binary(&1))

      valid? =
        is_list(run["runtimes"]) and run["runtimes"] != [] and
          run["runtimes"] -- @runtimes == [] and
          Enum.any?(@interfaces, &(&1["id"] == run["interface"])) and
          match?({:ok, _date}, Date.from_iso8601(to_string(run["date"]))) and
          is_binary(run["agent"]) and
          Enum.all?(~w(runtime_version model client), &text?.(run[&1])) and
          is_boolean(run["witnessed"]) and is_map(results) and
          results != %{} and
          if(together?,
            do: Map.keys(results) -- steps == [],
            else: Enum.sort(Map.keys(results)) == Enum.sort(steps)
          ) and
          Enum.all?(results, fn {_step, step} ->
            is_map(step) and step["result"] in @outcomes and
              Enum.all?(~w(at request_id note), &text?.(step[&1])) and
              (step["result"] in ["PASS", "NOT RUN"] or is_binary(step["note"])) and
              (not witnessed? or step["result"] != "PASS" or
                 (is_binary(step["at"]) and is_binary(step["request_id"])))
          end) and
          (not witnessed? or Enum.all?(~w(runtime_version model client), &is_binary(run[&1])))

      valid? ||
        raise ArgumentError,
              "#{file} doesn't follow the rules for a run in priv/keyfleet/agent_compatibility.yml"

      Map.merge(run, %{"id" => Path.basename(file, ".md"), "evidence" => String.trim(evidence)})
    end

  same_day =
    runs
    |> Enum.frequencies_by(&{&1["runtimes"], &1["interface"], &1["date"]})
    |> Enum.filter(fn {_run, count} -> count > 1 end)

  same_day == [] ||
    raise ArgumentError,
          "one run per runtime, connection and day; a rerun replaces that day's file: #{inspect(same_day)}"

  # Newest day first, so the first run that matches is the one a cell shows.
  @runs runs |> Enum.sort_by(& &1["id"]) |> Enum.sort_by(& &1["date"], :desc)

  # A new or removed run recompiles this module, as an edited one does.
  def __mix_recompile__?,
    do: @runs_directory |> Path.join("*.md") |> Path.wildcard() |> Enum.sort() != @run_files

  @doc """
  The line of Markdown under the name of a runtime that passed Keyfleet's
  checks through at least one connection: Verified through which, linked to its
  checks. Nil for any other runtime, and for a page the checks don't cover,
  such as Any agent.
  """
  def status(slug) when slug in @runtimes do
    case standing(slug) do
      nil -> nil
      line -> "#{line} [See each check](#{link(AgentGuides.name(slug))})."
    end
  end

  def status(_slug), do: nil

  defp standing(slug) do
    verified =
      for interface <- @interfaces,
          run <- List.wrap(newest_run(slug, interface)),
          verified?(run),
          do: interface["through"]

    if verified != [], do: "**Verified** through #{words(verified)}."
  end

  @doc "The page as Markdown, its addresses written from `{{origin}}`."
  def markdown do
    """
    # Agent compatibility

    An agent is Verified through a connection only after it has passed every check below that the connection offers, through that connection alone, at a recorded version, and Keyfleet has matched the run against its own records. A result marked * was reported by the agent and hasn't been checked by Keyfleet yet.

    Version #{@version}, #{day(@date)}.

    | Agent | #{Enum.map_join(@interfaces, " | ", & &1["name"])} |
    | --- |#{String.duplicate(" --- |", length(@interfaces))}
    #{Enum.map_join(@runtimes, "\n", &summary_row/1)}

    ## Checks

    Every run makes each check in the Regents Club through one connection:

    #{Enum.map_join(@interfaces, "\n", &"- **#{&1["name"]}**: #{&1["about"]}")}

    A result through one connection never counts for another. The proposal, treasury and Classic #1 checks only read: no run makes a payment or an on-chain transaction.

    | Check | Pass rule |
    | --- | --- |
    #{Enum.map_join(@checks, "\n", &"| #{&1["id"]} #{&1["name"]} | #{&1["passes"]} |")}

    ## Pair checks

    | Check | Pass rule | Result |
    | --- | --- | --- |
    #{Enum.map_join(@scenarios, "\n", &scenario_row/1)}

    #{Enum.map_join(@runtimes, "\n\n", &runtime_section/1)}

    ## Runs

    #{Enum.map_join(@runs, "\n\n", &run_section/1)}
    """
  end

  defp summary_row(slug) do
    states = Enum.map_join(@interfaces, " | ", &state(newest_run(slug, &1)))
    name = AgentGuides.name(slug)
    "| [#{name}](#{link(name)}) | #{states} |"
  end

  defp state(nil), do: "Not run"
  defp state(%{"witnessed" => false}), do: "Self-reported"
  defp state(run), do: if(verified?(run), do: "Verified", else: "Not passing")

  defp scenario_row(scenario) do
    result =
      case Enum.find(@runs, &Map.has_key?(&1["results"], scenario["id"])) do
        nil -> "Not run"
        run -> "#{cell(run, scenario)} (#{run_names(run)})"
      end

    "| #{scenario["id"]} #{scenario["name"]} | #{scenario["passes"]} | #{result} |"
  end

  defp runtime_section(slug) do
    name = AgentGuides.name(slug)
    setup = "[Set up #{name}]({{origin}}/keyfleet/agents/#{slug})."

    lead =
      case standing(slug) do
        nil -> setup
        line -> "#{line} #{setup}"
      end

    rows =
      Enum.map_join(@interfaces, "\n", fn interface ->
        run = newest_run(slug, interface)
        "| #{interface["name"]} | #{Enum.map_join(@checks, " | ", &cell(run, &1))} |"
      end)

    """
    ## #{name}

    #{lead}

    | Connection | #{Enum.map_join(@checks, " | ", & &1["id"])} |
    | --- |#{String.duplicate(" --- |", length(@checks))}
    #{rows}\
    """
  end

  defp run_section(run) do
    steps = Enum.filter(@checks ++ @scenarios, &Map.has_key?(run["results"], &1["id"]))

    rows =
      Enum.map_join(steps, "\n", fn step ->
        result = run["results"][step["id"]]

        "| #{step["id"]} #{step["name"]} | #{word(result["result"])} | #{known(result["at"])} | #{known(result["request_id"])} | #{text(result["note"])} |"
      end)

    who =
      if run["witnessed"],
        do: "Run by #{run["agent"]}. Keyfleet has matched it against its own records.",
        else:
          "Reported by #{run["agent"]}. Keyfleet hasn't matched it against its own records yet."

    """
    ### #{title(run)}

    #{who}

    | Runtime version | Model | Client |
    | --- | --- | --- |
    | #{known(run["runtime_version"])} | #{known(run["model"])} | #{known(run["client"])} |

    | Check | Result | Time (UTC) | Request id | Note |
    | --- | --- | --- | --- | --- |
    #{rows}

    #{run["evidence"]}\
    """
  end

  defp newest_run(slug, interface),
    do: Enum.find(@runs, &(&1["runtimes"] == [slug] and &1["interface"] == interface["id"]))

  defp verified?(run) do
    run["witnessed"] and
      Enum.all?(run["results"], fn {_step, step} ->
        step["result"] in ["PASS", "NOT SUPPORTED"]
      end)
  end

  # A result links to the run it came from; NOT RUN has no run behind it.
  defp cell(nil, _step), do: "Not run"

  defp cell(run, step) do
    case run["results"][step["id"]]["result"] do
      "NOT RUN" -> "Not run"
      result -> "[#{word(result)}#{if run["witnessed"], do: "", else: "*"}](#{link(title(run))})"
    end
  end

  # How each recorded result reads on the page.
  defp word("PASS"), do: "Passed"
  defp word("FAIL"), do: "Failed"
  defp word("BLOCKED"), do: "Blocked"
  defp word("NOT SUPPORTED"), do: "Not offered"
  defp word("NOT RUN"), do: "Not run"

  defp title(run) do
    interface = Enum.find(@interfaces, &(&1["id"] == run["interface"]))
    "#{run_names(run)} through #{interface["through"]}, #{day(run["date"])}"
  end

  defp run_names(run), do: run["runtimes"] |> Enum.map(&AgentGuides.name/1) |> words()

  # The address of a heading on this page: its text in lower case, without
  # punctuation, spaces as hyphens, as the page's headings are given ids.
  defp link(heading) do
    anchor =
      heading
      |> String.downcase()
      |> String.replace(~r/[^\p{L}\p{M}\p{N}\p{Pc} -]/u, "")
      |> String.replace(" ", "-")

    "{{origin}}/keyfleet/agents/compatibility##{anchor}"
  end

  defp day(date),
    do: date |> to_string() |> Date.from_iso8601!() |> Calendar.strftime("%-d %b %Y")

  defp words([one]), do: one
  defp words(many), do: Enum.join(Enum.drop(many, -1), ", ") <> " and " <> List.last(many)

  defp known(nil), do: "Not recorded"
  defp known(value), do: text(value)

  defp text(nil), do: ""
  defp text(value), do: String.replace(value, "|", "\\|")
end
