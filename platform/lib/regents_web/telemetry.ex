defmodule RegentsWeb.Telemetry do
  @moduledoc """
  The site's measurements, as `:telemetry` events, and their Prometheus export on
  the private metrics listener (`RegentsWeb.Metrics`). Ecto's
  `[:regents, :repo, :query]` gives each query's wait for a connection
  (`queue_time`, the `health.*` series Fly Sentinel reads from every site) and its
  whole time (`total_time`). Every request the router sends to a page or
  controller is timed by its route pattern (`[:phoenix, :router_dispatch, :stop]`),
  never by its path. Background jobs report each run's outcome and time from
  Oban's own events. Each staking chain read (`Regents.WalletActions.Rpc`) is
  counted by its purpose and method, and every chain request that got no answer
  by its method, class, chain and the caller's fixed scope
  (`[:regents, :chain, :failure]`, a `health.*` series).
  The engine's memory, run queues and process counts come from telemetry_poller's
  default poller.

  The reporter, Peep, keeps a fixed set of counters for each series and holds
  no observation between scrapes. It adds each observation to a running total
  as a whole number, so times are measured in whole microseconds, and every
  total stays exact.
  """

  import Telemetry.Metrics

  alias RegentsWeb.Telemetry.Buckets

  @reporter :regents_prometheus

  def child_spec(_arg) do
    Peep.child_spec(metrics: metrics(), name: @reporter)
  end

  @doc "Every measurement as Prometheus text, as the metrics listener answers it."
  def scrape,
    do: @reporter |> Peep.get_all_metrics() |> Peep.Prometheus.export() |> IO.iodata_to_binary()

  defp metrics do
    [
      counter("regents.privy.browser_failure.total", tags: [:reason]),
      distribution("health.db_queue.microseconds",
        event_name: [:regents, :repo, :query],
        measurement: :queue_time,
        unit: {:native, :microsecond},
        description: "Microseconds a query waited for a database connection",
        reporter_options: [
          peep_bucket_calculator: Buckets,
          buckets:
            [1_000, 5_000, 10_000, 25_000, 50_000, 100_000, 250_000, 500_000] ++
              [1_000_000, 2_500_000, 5_000_000]
        ]
      ),
      distribution("regents.repo.query.microseconds",
        event_name: [:regents, :repo, :query],
        measurement: :total_time,
        unit: {:native, :microsecond},
        description: "Microseconds each query took, waiting for a connection included",
        reporter_options: [
          peep_bucket_calculator: Buckets,
          buckets:
            [1_000, 5_000, 10_000, 25_000, 50_000, 100_000, 250_000, 500_000] ++
              [1_000_000, 2_500_000, 5_000_000]
        ]
      ),
      distribution("regents.request.duration.microseconds",
        event_name: [:phoenix, :router_dispatch, :stop],
        measurement: :duration,
        unit: {:native, :microsecond},
        tags: [:route],
        description: "Microseconds each request took, by its route pattern",
        reporter_options: [
          peep_bucket_calculator: Buckets,
          buckets:
            [5_000, 10_000, 25_000, 50_000, 100_000, 250_000, 500_000, 1_000_000] ++
              [2_500_000, 5_000_000, 10_000_000]
        ]
      ),
      counter("regents.jobs.finished.total",
        event_name: [:oban, :job, :stop],
        tags: [:queue, :worker, :state],
        description: "Job runs that ended done, cancelled or snoozed"
      ),
      counter("regents.jobs.failed.total",
        event_name: [:oban, :job, :exception],
        tags: [:queue, :worker, :state],
        description: "Job runs that failed; state says whether the job will retry"
      ),
      distribution("regents.jobs.duration.microseconds",
        event_name: [:oban, :job, :stop],
        measurement: :duration,
        unit: {:native, :microsecond},
        tags: [:queue, :worker],
        reporter_options: [
          peep_bucket_calculator: Buckets,
          buckets: [
            10_000,
            50_000,
            100_000,
            500_000,
            1_000_000,
            5_000_000,
            15_000_000,
            60_000_000
          ]
        ]
      ),
      counter("health.agent_activity_unread.total",
        event_name: [:regents, :agents, :activity_unread],
        tags: [:reason],
        description: "Agents' activity reads from the sign-in service that gave no reading"
      ),
      counter("health.chain_request_failures.total",
        event_name: [:regents, :chain, :failure],
        tags: [:method, :class, :chain_id, :scope],
        description: "Chain requests that got no answer"
      ),
      counter("regents.staking.rpc_requests.total",
        event_name: [:regents, :staking, :rpc],
        tags: [:purpose, :method, :chain_id, :environment],
        description: "Staking chain reads sent, by purpose and method"
      ),
      last_value("vm.memory.total.bytes", event_name: [:vm, :memory], measurement: :total),
      last_value("vm.memory.processes.bytes",
        event_name: [:vm, :memory],
        measurement: :processes
      ),
      last_value("vm.memory.binary.bytes", event_name: [:vm, :memory], measurement: :binary),
      last_value("vm.memory.ets.bytes", event_name: [:vm, :memory], measurement: :ets),
      last_value("vm.memory.code.bytes", event_name: [:vm, :memory], measurement: :code),
      last_value("vm.memory.atom.bytes", event_name: [:vm, :memory], measurement: :atom),
      last_value("vm.total_run_queue_lengths.total"),
      last_value("vm.total_run_queue_lengths.cpu"),
      last_value("vm.system_counts.process_count"),
      last_value("vm.system_counts.atom_count"),
      last_value("vm.system_counts.port_count")
    ]
  end
end
