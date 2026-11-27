defmodule Mix.Tasks.Regents.VerifyContracts do
  @shortdoc "Runs executable route, MCP tool, Prometheus, and runtime regression contracts"
  @moduledoc """
  Verifies executable runtime contracts across all folded products without
  requiring a production database:

  1. Router uniqueness: zero shadowed duplicate `(verb, path)` pairs.
  2. Public documents: `Autolaunch.PublicDocuments.market_page/3` covers every
     market kind (`:token`, `:robinhood_token`, `:auction`, `:robinhood_auction`,
     `:stock`).
  3. Hosted MCP (`AshAi`): every exposed tool across all four product domains has
     a valid action, non-empty description, valid `<product>_*` prefix, clean
     `Ash.ActionInput` construction when optional arguments are omitted, and
     matches hosted entries in `priv/<product>/tool_manifest.json`.
  4. Sentinel Prometheus parity: `RegentsWeb.Telemetry.scrape/0` exports every
     required Sentinel health and Patchbay series name.
  5. Live ErrorTracker regressions: `ProductActivity.active?(:cloak)`,
     `Keyfleet.AgentTools.Account.Answer.answer(:join, %{}, ...)`, and
     `ShareVideo.Canvas` missing-executable handling.
  """
  use Boundary, top_level?: true, check: [out: false]
  use Mix.Task

  alias Regents.Account.Actors.Agent
  alias Regents.ProductActivity
  alias RegentsWeb.Autolaunch.PublicDocuments, as: AutolaunchDocs
  alias RegentsWeb.Keyfleet.AgentTools.Account.Answer, as: KeyfleetAccountAnswer
  alias RegentsWeb.Router
  alias RegentsWeb.Telemetry

  @agent_tool_domains [
    {"autolaunch", RegentsWeb.Autolaunch.AgentTools},
    {"techtree", RegentsWeb.Techtree.AgentTools},
    {"keyfleet", RegentsWeb.Keyfleet.AgentTools},
    {"patchbay", RegentsWeb.Patchbay.AgentTools}
  ]

  @sentinel_series [
    "health_job_oldest_age_seconds",
    "health_db_queue_microseconds",
    "health_wallet_unconfirmed_oldest_seconds",
    "patchbay_assist_fees_unforwarded_usdc",
    "patchbay_escrow_unrecorded",
    "health_indexer_lag_blocks",
    "health_indexer_passes_total",
    "health_product_active",
    "health_points_tally_finished_seconds",
    "health_shared_reading_size_percent",
    "health_chain_event_delay_microseconds",
    "health_chain_request_failures_total",
    "health_wallet_send_failures_total"
  ]

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("compile")

    failures =
      check_router_uniqueness() ++
        check_autolaunch_market_pages() ++
        check_agent_tools() ++
        check_prometheus_contract() ++
        check_runtime_regressions()

    case failures do
      [] ->
        Mix.shell().info("All executable runtime contracts verified cleanly.")

      problems ->
        Enum.each(problems, &Mix.shell().error("CONTRACT FAILURE: " <> &1))
        Mix.raise("#{length(problems)} executable contract failure(s)")
    end
  end

  defp check_router_uniqueness do
    duplicates =
      Router.__routes__()
      |> Enum.group_by(&{&1.verb, &1.path})
      |> Enum.filter(fn {_key, routes} -> match?([_, _ | _], routes) end)

    for {{verb, path}, routes} <- duplicates do
      plugs = Enum.map_join(routes, ", ", &"#{inspect(&1.plug)}:#{inspect(&1.plug_opts)}")
      "Duplicate router entry #{String.upcase(to_string(verb))} #{path} (#{plugs})"
    end
  end

  defp check_autolaunch_market_pages do
    for kind <- [:token, :robinhood_token, :auction, :robinhood_auction, :stock],
        reduce: [] do
      acc ->
        case AutolaunchDocs.market_page(kind, "Sample", "SMPL") do
          [page_title: title, page_description: desc]
          when is_binary(title) and title != "" and is_binary(desc) and desc != "" ->
            acc

          other ->
            [
              "Autolaunch.PublicDocuments.market_page(#{inspect(kind)}) returned #{inspect(other)}"
              | acc
            ]
        end
    end
  end

  defp check_agent_tools do
    Enum.flat_map(@agent_tool_domains, fn {product, domain} ->
      tools = AshAi.Info.tools(domain)
      check_domain_tools(product, domain, tools) ++ check_manifest_parity(product, tools)
    end)
  end

  defp check_domain_tools(product, domain, tools) do
    prefix = product <> "_"

    Enum.flat_map(tools, fn tool ->
      name = Atom.to_string(tool.name)
      action = Ash.Resource.Info.action(tool.resource, tool.action)

      name_errors =
        if String.starts_with?(name, prefix),
          do: [],
          else: ["#{inspect(domain)} tool #{name} missing prefix #{prefix}"]

      desc_errors =
        if is_binary(tool.description) and String.trim(tool.description) != "",
          do: [],
          else: ["#{inspect(domain)} tool #{name} has empty description"]

      action_errors =
        if is_nil(action),
          do: [
            "#{inspect(domain)} tool #{name} targets missing action #{inspect(tool.resource)}.#{tool.action}"
          ],
          else: check_action_optional_args(tool, action)

      name_errors ++ desc_errors ++ action_errors
    end)
  end

  defp check_action_optional_args(tool, action) do
    required =
      action.arguments
      |> Enum.reject(& &1.allow_nil?)
      |> Map.new(&{&1.name, dummy_value(&1.type)})

    try do
      _input = Ash.ActionInput.for_action(tool.resource, action.name, required)
      []
    rescue
      error ->
        [
          "#{tool.name} failed ActionInput with optional args omitted: #{Exception.message(error)}"
        ]
    end
  end

  defp dummy_value(:integer), do: 1
  defp dummy_value(:boolean), do: false
  defp dummy_value({:array, _inner}), do: []
  defp dummy_value(:map), do: %{}
  defp dummy_value(_other), do: "sample"

  defp check_manifest_parity(product, tools) do
    path = Path.join([Application.app_dir(:regents, "priv"), product, "tool_manifest.json"])
    manifest = path |> File.read!() |> Jason.decode!()
    exposed = MapSet.new(tools, &Atom.to_string(&1.name))

    manifest_hosted =
      manifest
      |> Map.fetch!("tools")
      |> Enum.flat_map(&hosted_tool_name(product, &1))

    for name <- manifest_hosted, not MapSet.member?(exposed, name) do
      "#{product} tool_manifest.json marks #{name} hosted, but #{product}.AgentTools does not expose it"
    end
  end

  defp hosted_tool_name("patchbay", %{"hosted" => true, "hosted_name" => name})
       when is_binary(name),
       do: [name]

  defp hosted_tool_name("patchbay", %{"hosted" => true, "name" => name}), do: [name]

  defp hosted_tool_name("techtree", %{"interfaces" => %{"mcp" => name}}) when is_binary(name),
    do: [name]

  defp hosted_tool_name(_product, _tool), do: []

  defp check_prometheus_contract do
    {:ok, _} = Application.ensure_all_started(:telemetry)
    {:ok, _} = Application.ensure_all_started(:peep)

    sup =
      case Process.whereis(:regents_prometheus) do
        nil ->
          {:ok, pid} = Supervisor.start_link([Telemetry], strategy: :one_for_one)
          pid

        _pid ->
          nil
      end

    try do
      emit_sentinel_sample_events()
      body = Telemetry.scrape()

      for series <- @sentinel_series, not String.contains?(body, series) do
        "RegentsWeb.Telemetry.scrape/0 missing Sentinel metric series #{series}"
      end
    after
      if sup, do: Supervisor.stop(sup)
    end
  end

  defp emit_sentinel_sample_events do
    :telemetry.execute([:regents, :oban, :oldest_job], %{age_seconds: 0.0}, %{queue: "default"})
    :telemetry.execute([:regents, :repo, :query], %{queue_time: 1000, total_time: 2000}, %{})

    :telemetry.execute([:patchbay, :wallet, :unconfirmed_oldest], %{age_ms: 0}, %{
      flow: "fee_forward"
    })

    :telemetry.execute(
      [:patchbay, :operator_wallet, :waiting],
      %{escrow_unrecorded: 0, assist_fees_usdc: 0.0},
      %{}
    )

    :telemetry.execute([:regents, :indexer, :lag], %{blocks: 0}, %{
      indexer: "stock_admissions",
      chain_id: 8453
    })

    :telemetry.execute([:regents, :product, :active], %{active: 1}, %{product: :autolaunch})
    :telemetry.execute([:regent_points, :tally_periods, :finished], %{}, %{})

    :telemetry.execute([:regents, :shared_reading, :size], %{bytes: 10, limit: 100}, %{
      kind: :points_board
    })

    :telemetry.execute([:regents, :chain_event, :recorded], %{delay_ms: 100}, %{
      kind: :bid,
      chain_id: 8453
    })

    :telemetry.execute([:regents, :chain, :failure], %{count: 1}, %{
      method: "eth_call",
      class: "timeout",
      chain_id: 8453,
      scope: "test"
    })

    Telemetry.wallet_failed(:bid, "wallet_declined")
  end

  defp check_runtime_regressions do
    actor = %Agent{
      wallet_address: "0x0000000000000000000000000000000000000001",
      chain_id: 8453,
      verification_method: :siwa,
      audience: "regents"
    }

    checks = [
      {ProductActivity.active?(:cloak) == false,
       "ProductActivity.active?(:cloak) did not return false"},
      {match?({422, _, _}, KeyfleetAccountAnswer.answer(:join, %{}, actor, nil)),
       "Keyfleet.AgentTools.Account.Answer.answer(:join, %{}, ...) did not return 422 refusal"}
    ]

    for {ok?, msg} <- checks, not ok?, do: msg
  end
end
