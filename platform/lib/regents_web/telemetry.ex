defmodule RegentsWeb.Telemetry do
  @moduledoc """
  The site's measurements, as `:telemetry` events, and their Prometheus export on
  the private metrics listener (`RegentsWeb.Metrics`). Ecto's
  `[:regents, :repo, :query]` gives each query's wait for a connection
  (`queue_time`, the `health.*` series Fly Sentinel reads from every site) and its
  whole time (`total_time`). Every request the router sends to a page or
  controller is timed by its route pattern (`[:phoenix, :router_dispatch, :stop]`),
  never by its path. Background jobs report each run's outcome and time from
  Oban's own events. Each staking chain read (`Regents.Chain.Rpc`) is
  counted by its purpose and method, and every chain request that got no answer
  by its method, class, chain and the caller's fixed scope
  (`[:regents, :chain, :failure]`, a `health.*` series). Each time the Points
  tally of finished periods runs to its end (`[:regent_points, :tally_periods,
  :finished]`), the clock time it finished is kept as a `health.*` gauge, so a
  stalled tally shows as a time that stops moving.
  The size of each reading offered to `Regents.SharedReading` is kept as a
  percent of its kind's limit (`health.shared_reading.size.percent`), so the
  Points board shows nearing its limit before it is refused.
  The engine's memory, run queues and process counts come from telemetry_poller's
  default poller.

  The reporter, Peep, keeps a fixed set of counters for each series and holds
  no observation between scrapes. It adds each observation to a running total
  as a whole number, so times are measured in whole microseconds, and every
  total stays exact.
  """

  import Telemetry.Metrics

  require Logger

  alias Regents.Patchbay.OperatorWallet
  alias RegentsWeb.Telemetry.Buckets

  @reporter :regents_prometheus

  # Bounded allowlist of wallet send failure reasons reported across Keyfleet
  # and Autolaunch wallet hooks so Prometheus labels stay bounded.
  @wallet_failures ~w(
    step_unknown
    blocked
    calls_failed
    wallet_unavailable
    switch_declined
    network_mismatch
    wallet_declined
    insufficient_funds
    send_unconfirmed
    sign_unconfirmed
  )

  def child_spec(_arg) do
    Peep.child_spec(metrics: metrics(), name: @reporter)
  end

  @doc """
  Counts one wallet send/sign failure across any folded product (`flow` is the
  bounded flow name, `reason` is checked against the bounded allowlist).
  """
  def wallet_failed(flow, reason) when reason in @wallet_failures do
    :telemetry.execute([:regents, :wallet, :failure], %{count: 1}, %{
      flow: to_string(flow),
      reason: reason
    })
  end

  def wallet_failed(_flow, _reason), do: :ok

  @doc "Every measurement as Prometheus text, as the metrics listener answers it."
  def scrape,
    do: @reporter |> Peep.get_all_metrics() |> Peep.Prometheus.export() |> IO.iodata_to_binary()

  @doc "The poller for the measurements the site takes itself, started after Oban."
  def site_poller do
    {:telemetry_poller,
     measurements: [
       {__MODULE__, :operator_wallet_waiting, []},
       {__MODULE__, :oldest_unconfirmed_sends, []}
     ],
     period: 10_000,
     name: :regents_site_poller}
  end

  # The poller drops for good a measurement that raises or exits, so whatever
  # stops this tick (a database or Oban hiccup) is logged and skipped.
  @doc false
  def operator_wallet_waiting do
    if patchbay_fees_running?() do
      :telemetry.execute(
        [:patchbay, :operator_wallet, :waiting],
        %{
          escrow_unrecorded: OperatorWallet.escrow_unrecorded(),
          assist_fees_usdc: OperatorWallet.assist_fees_unforwarded_usdc()
        },
        %{}
      )
    end

    :ok
  rescue
    error -> not_measured("operator wallet numbers", Exception.message(error))
  catch
    :exit, reason -> not_measured("operator wallet numbers", Exception.format_exit(reason))
  end

  @doc false
  def oldest_unconfirmed_sends do
    if patchbay_fees_running?() do
      now = DateTime.utc_now()

      for {flow, signed_at} <- OperatorWallet.unconfirmed_sends() do
        :telemetry.execute(
          [:patchbay, :wallet, :unconfirmed_oldest],
          %{age_ms: unconfirmed_age_ms(now, signed_at)},
          %{flow: flow}
        )
      end
    end

    :ok
  rescue
    error -> not_measured("unconfirmed send age", Exception.message(error))
  catch
    :exit, reason -> not_measured("unconfirmed send age", Exception.format_exit(reason))
  end

  defp unconfirmed_age_ms(_now, nil), do: 0
  defp unconfirmed_age_ms(now, signed_at), do: DateTime.diff(now, signed_at, :millisecond)

  defp patchbay_fees_running? do
    Enum.any?(Oban.check_all_queues(), &(&1.queue == "patchbay_fees" and not &1.paused))
  end

  defp not_measured(what, why), do: Logger.warning("#{what} not measured: #{why}")

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
      counter("health.wallet_send_failures.total",
        event_name: [:regents, :wallet, :failure],
        tags: [:flow, :reason],
        description: "Wallet presses that were not sent, not confirmed or refused"
      ),
      last_value("health.wallet_unconfirmed_oldest.seconds",
        event_name: [:patchbay, :wallet, :unconfirmed_oldest],
        measurement: :age_ms,
        unit: {:millisecond, :second},
        tags: [:flow],
        description:
          "Age of the oldest transaction the site's own wallet signed that is not yet confirmed"
      ),
      last_value("patchbay.escrow_unrecorded",
        event_name: [:patchbay, :operator_wallet, :waiting],
        measurement: :escrow_unrecorded,
        description: "Paid priority reports whose escrow credit the chain has not yet confirmed"
      ),
      last_value("patchbay.assist_fees_unforwarded.usdc",
        event_name: [:patchbay, :operator_wallet, :waiting],
        measurement: :assist_fees_usdc,
        description: "Assist fees the operator holds that are not yet sent to staking"
      ),
      last_value("health.indexer.lag.blocks",
        event_name: [:regents, :indexer, :lag],
        measurement: :blocks,
        tags: [:indexer, :chain_id],
        description: "Blocks behind head reported at the end of each chain indexer pass"
      ),
      counter("health.indexer.passes.total",
        event_name: [:regents, :indexer, :lag],
        tags: [:indexer, :chain_id],
        description: "Completed chain indexer passes, by indexer and chain"
      ),
      distribution("health.chain_event.delay.microseconds",
        event_name: [:regents, :chain_event, :recorded],
        measurement: :delay_ms,
        unit: {:millisecond, :microsecond},
        tags: [:kind, :chain_id],
        description: "Microseconds between an on-chain bid/trade and recording it",
        reporter_options: [
          peep_bucket_calculator: Buckets,
          buckets: [
            1_000_000,
            5_000_000,
            15_000_000,
            30_000_000,
            60_000_000,
            120_000_000,
            300_000_000,
            600_000_000
          ]
        ]
      ),
      last_value("health.product.active",
        event_name: [:regents, :product, :active],
        measurement: :active,
        tags: [:product],
        description: "1 while a product's routes are active, 0 while its background readers sleep"
      ),
      last_value("health.points_tally_finished.seconds",
        event_name: [:regent_points, :tally_periods, :finished],
        measurement: fn _measurements -> System.system_time(:second) end,
        description:
          "When the Points tally of finished periods last ran to its end, in Unix seconds"
      ),
      counter("regents.staking.rpc_requests.total",
        event_name: [:regents, :staking, :rpc],
        tags: [:purpose, :method, :chain_id, :environment],
        description: "Staking chain reads sent, by purpose and method"
      ),
      last_value("health.shared_reading.size.percent",
        event_name: [:regents, :shared_reading, :size],
        measurement: &div(&1.bytes * 100, &1.limit),
        tags: [:kind],
        description:
          "Size of the last reading each kind was offered, as a percent of the kind's limit; " <>
            "past 100 it is refused and the last one held stays"
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
