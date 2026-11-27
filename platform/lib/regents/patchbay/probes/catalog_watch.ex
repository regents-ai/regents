defmodule Regents.Patchbay.Probes.CatalogWatch do
  @moduledoc """
  Scheduled SSRF-safe probe worker for Patchbay's curated commerce service
  catalog (`priv/patchbay/data/commerce_services.json`).

  Probes each service's declared `probe_url` using its `probe_method` and
  `probe_mode`:
  - `"payment_402"`: runs full `PaymentEndpoint.probe/2` (HTTP 402 challenge +
    `OPTIONS` CORS preflight + header checks).
  - `"discovery_200"`: performs a bounded public HTTPS reachability check via
    `RegentHttp.Public.request/3` and records HTTP status, latency, and health.

  Results are stored in `Regents.Patchbay.Probes.CatalogStore` and broadcast
  across nodes via `Regents.PubSub`.
  """

  use Oban.Worker,
    queue: :patchbay_outside_calls,
    max_attempts: 1,
    unique: [period: 300, states: :incomplete]

  alias RegentHttp.Public
  alias Regents.Patchbay.Commerce.Catalog
  alias Regents.Patchbay.Probes.CatalogStore
  alias Regents.Patchbay.Probes.PaymentEndpoint

  @discovery_timeout_ms 6_000
  @max_discovery_bytes 16_384

  @impl Oban.Worker
  def perform(%Oban.Job{} = job) do
    if Regents.ProductActivity.cron_allowed?(:patchbay, job) do
      refresh_now()
      :ok
    else
      :ok
    end
  end

  @doc "Run a live probe sweep across all curated catalog services and persist results."
  @spec refresh_now() :: {:ok, %{probed: non_neg_integer(), healthy: non_neg_integer()}}
  def refresh_now do
    services = Catalog.raw_services()

    snapshots =
      services
      |> Task.async_stream(&probe_service/1,
        max_concurrency: 4,
        timeout: 12_000,
        on_timeout: :kill_task,
        ordered: false
      )
      |> Enum.reduce(%{}, fn
        {:ok, {slug, snap}}, acc -> Map.put(acc, slug, snap)
        {:exit, _reason}, acc -> acc
      end)

    CatalogStore.put_all(snapshots)

    healthy = Enum.count(Map.values(snapshots), &(&1.status == "healthy"))
    {:ok, %{probed: map_size(snapshots), healthy: healthy}}
  end

  defp probe_service(service) do
    slug = service["slug"]
    url = service["probe_url"]
    method = service["probe_method"] || "GET"
    mode = service["probe_mode"] || "discovery_200"

    snap =
      cond do
        not is_binary(url) or url == "" ->
          unchecked_snapshot(mode)

        mode == "payment_402" ->
          probe_payment_endpoint(url, method)

        true ->
          probe_discovery_endpoint(url, method)
      end

    {slug, snap}
  end

  defp probe_payment_endpoint(url, method) do
    case PaymentEndpoint.probe(url, method) do
      {:ok, result} ->
        failing =
          result.checks
          |> Enum.filter(&(&1.level == :fail))
          |> Enum.map(& &1.code)

        warnings =
          result.checks
          |> Enum.filter(&(&1.level == :warn))
          |> Enum.map(& &1.code)

        status =
          case result.verdict do
            :pass -> "healthy"
            :warn -> "degraded"
            _fail -> "failing"
          end

        %{
          mode: "payment_402",
          status: status,
          http_status: result.status,
          verdict: Atom.to_string(result.verdict),
          latency_ms: result.latency_ms,
          detected_protocols: result.detected_protocols,
          cors_preflight_ok: get_in(result, [:cors, :preflight_ok]),
          failing_checks: failing,
          warning_checks: warnings,
          checked_at: result.checked_at
        }

      {:error, reason} ->
        %{
          mode: "payment_402",
          status: "failing",
          http_status: nil,
          verdict: "fail",
          latency_ms: nil,
          detected_protocols: [],
          cors_preflight_ok: false,
          failing_checks: ["unreachable"],
          warning_checks: [],
          error: reason,
          checked_at: DateTime.utc_now() |> DateTime.to_iso8601()
        }
    end
  end

  defp probe_discovery_endpoint(url, method) do
    req_method =
      case String.upcase(method) do
        "POST" -> :post
        "HEAD" -> :head
        _ -> :get
      end

    opts = [
      max_bytes: @max_discovery_bytes,
      timeout: @discovery_timeout_ms,
      headers: [
        {"accept", "application/json, text/html, */*"},
        {"user-agent", "Patchbay-CatalogWatch/1.0 (+https://regents.sh/patchbay/app)"}
      ]
    ]

    started = System.monotonic_time(:millisecond)

    case Public.request(req_method, url, opts) do
      {:ok, response} ->
        elapsed = System.monotonic_time(:millisecond) - started
        ok? = response.status in 200..399

        %{
          mode: "discovery_200",
          status: if(ok?, do: "healthy", else: "failing"),
          http_status: response.status,
          verdict: if(ok?, do: "pass", else: "fail"),
          latency_ms: elapsed,
          detected_protocols: [],
          cors_preflight_ok: nil,
          failing_checks: if(ok?, do: [], else: ["http_#{response.status}"]),
          warning_checks: [],
          checked_at: DateTime.utc_now() |> DateTime.to_iso8601()
        }

      {:error, reason} ->
        %{
          mode: "discovery_200",
          status: "failing",
          http_status: nil,
          verdict: "fail",
          latency_ms: nil,
          detected_protocols: [],
          cors_preflight_ok: nil,
          failing_checks: [to_string(reason)],
          warning_checks: [],
          checked_at: DateTime.utc_now() |> DateTime.to_iso8601()
        }
    end
  end

  defp unchecked_snapshot(mode) do
    %{
      mode: mode,
      status: "unchecked",
      http_status: nil,
      verdict: nil,
      latency_ms: nil,
      detected_protocols: [],
      cors_preflight_ok: nil,
      failing_checks: [],
      warning_checks: [],
      checked_at: nil
    }
  end
end
