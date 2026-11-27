defmodule Regents.Patchbay.Commerce.Catalog do
  @moduledoc """
  Curated agentic commerce services and endpoints tracked by Patchbay across
  x402 (Base / Solana), MPP (Tempo / Stripe), Cybersecurity (`cve.now`), MCP,
  and WebMCP. Loaded from `priv/patchbay/data/commerce_services.json` at
  compile time with zero external runtime dependencies.
  """

  alias Regents.Patchbay.Probes.CatalogStore

  @data_path "priv/patchbay/data/commerce_services.json"
  @external_resource @data_path
  @document @data_path |> File.read!() |> Jason.decode!()
  @services @document["services"] || []
  @updated_at @document["updated_at"]

  @protocols ~w(x402 mpp webmcp mcp siwa llms_txt)
  @rails ~w(base:usdc tempo:usdc_e tempo:pathusd solana:usdc stripe:link free)

  @doc "Unenriched curated catalog records (used by `CatalogWatch` prober)."
  @spec raw_services() :: [map()]
  def raw_services, do: @services

  @doc "All curated commerce services ordered by featured rank, enriched with live probe telemetry."
  @spec all() :: [map()]
  def all do
    probes = CatalogStore.all_map()
    Enum.map(@services, &attach_live_probe(&1, probes))
  end

  @doc "Date string recording when the curated catalog was last refreshed."
  @spec updated_at() :: String.t() | nil
  def updated_at, do: @updated_at

  @doc "Known protocol filter tokens."
  @spec protocols() :: [String.t()]
  def protocols, do: @protocols

  @doc "Known payment rail filter tokens."
  @spec rails() :: [String.t()]
  def rails, do: @rails

  @doc "Distinct service categories present in the catalog."
  @spec categories() :: [String.t()]
  def categories do
    @services
    |> Enum.map(& &1["category"])
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc "Look up a service by slug or registrable domain."
  @spec get(String.t()) :: map() | nil
  def get(ref) when is_binary(ref) do
    needle = ref |> String.trim() |> String.downcase()

    case Enum.find(@services, fn s -> s["slug"] == needle or s["domain"] == needle end) do
      nil -> nil
      service -> attach_live_probe(service, CatalogStore.all_map())
    end
  end

  def get(_other), do: nil

  @doc "Filter services by query text, protocol, payment rail, category, verification, and sort."
  @spec filter(map()) :: [map()]
  def filter(params \\ %{}) do
    q = normalize(params["q"])
    protocol = normalize(params["protocol"])
    rail = normalize(params["rail"])
    category = normalize(params["category"])
    verified? = params["verified"] in ["true", "1", true]
    sort = normalize(params["sort"])
    probes = CatalogStore.all_map()

    @services
    |> Enum.filter(fn service ->
      matches_query?(service, q) and
        matches_protocol?(service, protocol) and
        matches_rail?(service, rail) and
        matches_category?(service, category) and
        (not verified? or service["verified"] == true)
    end)
    |> sort_services(sort)
    |> Enum.map(&attach_live_probe(&1, probes))
  end

  @doc "Flattened list of endpoints across matching services."
  @spec endpoints(map()) :: [map()]
  def endpoints(params \\ %{}) do
    protocol = normalize(params["protocol"])

    params
    |> filter()
    |> Enum.flat_map(fn service ->
      Enum.map(service["endpoints"] || [], fn ep ->
        Map.merge(ep, %{
          "service_name" => service["name"],
          "service_slug" => service["slug"],
          "domain" => service["domain"],
          "category" => service["category"],
          "verified" => service["verified"]
        })
      end)
    end)
    |> Enum.filter(fn ep -> protocol == "" or ep["protocol"] == protocol end)
  end

  @doc "Aggregate counts by protocol, rail, and live probe status for telemetry cards."
  @spec summary() :: map()
  def summary do
    all_endpoints = Enum.flat_map(@services, &(&1["endpoints"] || []))
    probes = CatalogStore.all_map() |> Map.values()

    last_probe_at =
      probes
      |> Enum.map(& &1[:checked_at])
      |> Enum.reject(&is_nil/1)
      |> Enum.max(fn -> nil end)

    %{
      services: length(@services),
      endpoints: length(all_endpoints),
      x402_services: Enum.count(@services, &("x402" in (&1["protocols"] || []))),
      mpp_services: Enum.count(@services, &("mpp" in (&1["protocols"] || []))),
      webmcp_services: Enum.count(@services, &("webmcp" in (&1["protocols"] || []))),
      mcp_services: Enum.count(@services, &("mcp" in (&1["protocols"] || []))),
      tempo_services:
        Enum.count(@services, fn s ->
          rails = s["rails"] || []
          "tempo:usdc_e" in rails or "tempo:pathusd" in rails
        end),
      base_services: Enum.count(@services, &("base:usdc" in (&1["rails"] || []))),
      probed_services: length(probes),
      healthy_services: Enum.count(probes, &(&1[:status] == "healthy")),
      degraded_services: Enum.count(probes, &(&1[:status] == "degraded")),
      failing_services: Enum.count(probes, &(&1[:status] == "failing")),
      last_probe_at: last_probe_at
    }
  end

  defp attach_live_probe(service, probes) do
    case Map.get(probes, service["slug"]) do
      nil ->
        Map.merge(service, %{
          "status" => "unchecked",
          "http_status" => nil,
          "latency_ms" => nil,
          "last_checked_at" => nil,
          "live_probe" => nil
        })

      snap ->
        Map.merge(service, %{
          "status" => snap.status,
          "http_status" => snap.http_status,
          "latency_ms" => snap.latency_ms,
          "last_checked_at" => snap.checked_at,
          "live_probe" => snap
        })
    end
  end

  defp matches_query?(_service, ""), do: true

  defp matches_query?(service, q) do
    endpoints_text =
      Enum.map_join(service["endpoints"] || [], " ", fn ep ->
        "#{ep["method"]} #{ep["path"]} #{ep["description"]} #{ep["protocol"]}"
      end)

    haystack =
      [
        service["name"],
        service["domain"],
        service["category"],
        service["summary"],
        Enum.join(service["protocols"] || [], " "),
        Enum.join(service["rails"] || [], " "),
        endpoints_text
      ]
      |> Enum.join(" ")
      |> String.downcase()

    q
    |> String.split()
    |> Enum.all?(&String.contains?(haystack, &1))
  end

  defp matches_protocol?(_service, ""), do: true
  defp matches_protocol?(service, protocol), do: protocol in (service["protocols"] || [])

  defp matches_rail?(_service, ""), do: true
  defp matches_rail?(service, rail), do: rail in (service["rails"] || [])

  defp matches_category?(_service, ""), do: true
  defp matches_category?(service, category), do: service["category"] == category

  defp sort_services(list, "az"), do: Enum.sort_by(list, &String.downcase(&1["name"] || ""))

  defp sort_services(list, "za"),
    do: Enum.sort_by(list, &String.downcase(&1["name"] || ""), :desc)

  defp sort_services(list, _featured),
    do: Enum.sort_by(list, &{&1["featured_rank"] || 999, String.downcase(&1["name"] || "")})

  defp normalize(value) when is_binary(value), do: value |> String.trim() |> String.downcase()
  defp normalize(_other), do: ""
end
