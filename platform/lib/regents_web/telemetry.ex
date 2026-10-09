defmodule RegentsWeb.Telemetry do
  @moduledoc """
  The site's measurements and their Prometheus export on the private metrics
  listener (`RegentsWeb.Metrics`). The engine's memory, run queues and process
  counts come from telemetry_poller's default poller, every 10 seconds
  (`config/config.exs`).
  """
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      {TelemetryMetricsPrometheus.Core,
       metrics: prometheus_metrics(), name: prometheus_reporter(), start_async: false}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def prometheus_reporter, do: :regents_prometheus

  def prometheus_metrics do
    [
      counter("regents.privy.browser_failure.total", tags: [:reason]),
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
