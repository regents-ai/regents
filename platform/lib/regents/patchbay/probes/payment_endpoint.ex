defmodule Regents.Patchbay.Probes.PaymentEndpoint do
  @moduledoc """
  SSRF-hardened live HTTP 402 protocol validator for Agentic Commerce endpoints.

  Probes an `https://` endpoint (or Patchbay's own local sandboxes) and inspects:
  - **x402 v2**: `PAYMENT-REQUIRED` / `X-PAYMENT-REQUIRED` header decoding,
    `accepts[]` (`scheme`, CAIP-2 `network`, `asset`, `payTo`, `maxAmountRequired`),
    `extensions.bazaar` discovery schema checks, and browser CORS header exposure.
  - **MPP (Machine Payments Protocol / Tempo / Stripe)**:
    `WWW-Authenticate: Payment` header parsing (`id`, `realm`, `method`, `intent`,
    `expires`, base64url `request` JSON payload), Tempo `USDC.e`/`pathUSD` and
    `charge` vs `session` checks, `Cache-Control: no-store` and `Vary: Authorization`.
  - **Dual-protocol parity**: verifies consistency when an endpoint advertises both
    x402 and MPP challenges on the same `402` response.
  """

  alias RegentHttp.Public

  @allowed_methods ~w(GET POST HEAD)
  @max_url_bytes 512
  @max_body_bytes 32_768
  @timeout_ms 8_000

  @doc """
  Probe `url` using `method` (`"GET"`, `"POST"`, or `"HEAD"`).
  Returns `{:ok, diagnostic_map}` or `{:error, reason_string}`.
  """
  @spec probe(String.t(), String.t()) :: {:ok, map()} | {:error, String.t()}
  def probe(url, method \\ "GET")

  def probe(url, method) when is_binary(url) and is_binary(method) do
    normalized_method = method |> String.trim() |> String.upcase()
    trimmed_url = String.trim(url)

    with :ok <- validate_method(normalized_method),
         :ok <- validate_public_https_uri(trimmed_url),
         {:ok, response} <- perform_request(trimmed_url, normalized_method) do
      {:ok, analyze_response(trimmed_url, normalized_method, response)}
    end
  end

  def probe(_url, _method), do: {:error, "Provide a valid https:// URL and HTTP method."}

  defp validate_method(method) when method in @allowed_methods, do: :ok
  defp validate_method(_method), do: {:error, "Method must be GET, POST, or HEAD."}

  defp validate_public_https_uri(url) when byte_size(url) > @max_url_bytes,
    do: {:error, "URL exceeds #{@max_url_bytes} bytes."}

  defp validate_public_https_uri(url) do
    case Public.uri(url) do
      {:ok, %URI{host: host, port: 443}} ->
        if blocked_host?(String.downcase(host)),
          do: {:error, "Private, local, or internal hostnames cannot be probed."},
          else: :ok

      _other ->
        {:error, "Only public https:// endpoints on port 443 can be validated."}
    end
  end

  defp blocked_host?(host) do
    not String.contains?(host, ".") or
      String.ends_with?(host, [".local", ".internal", ".localhost", ".flycast", ".arpa"])
  end

  defp perform_request(url, method) do
    req_method =
      case method do
        "GET" -> :get
        "POST" -> :post
        "HEAD" -> :head
      end

    opts = [
      max_bytes: @max_body_bytes,
      timeout: @timeout_ms,
      body_statuses: [402],
      headers: [
        {"accept", "application/json, text/plain, */*"},
        {"user-agent", "Patchbay-Validator/1.0 (+https://regents.sh/patchbay/validate)"}
      ]
    ]

    opts =
      if req_method == :post,
        do:
          Keyword.merge(opts,
            body: "{}",
            headers: [{"content-type", "application/json"} | opts[:headers]]
          ),
        else: opts

    started = System.monotonic_time(:millisecond)

    case Public.request(req_method, url, opts) do
      {:ok, response} ->
        elapsed = System.monotonic_time(:millisecond) - started
        {:ok, %{response: response, latency_ms: elapsed}}

      {:error, reason} when reason in [:dns_error, :non_public_address] ->
        {:error, "Target hostname did not resolve to a public IP address."}

      {:error, :too_large} ->
        {:error, "Endpoint response exceeds #{@max_body_bytes} bytes."}

      {:error, reason} ->
        {:error, "Endpoint could not be reached (#{reason})."}
    end
  end

  defp analyze_response(url, method, %{response: response, latency_ms: latency_ms}) do
    headers = normalize_headers(response.headers)
    parsed_body = parse_json(response.body || "")

    x402 = inspect_x402(headers, parsed_body)
    mpp = inspect_mpp(headers)
    checks = build_checks(response.status, headers, x402, mpp)
    detected = detected_protocols(x402, mpp)
    known_fix_ids = suggested_known_fixes(response.status, headers, x402, mpp)

    verdict =
      cond do
        response.status == 402 and detected != [] and Enum.all?(checks, &(&1.level != :fail)) ->
          :pass

        response.status == 402 and detected != [] ->
          :warn

        true ->
          :fail
      end

    %{
      url: url,
      method: method,
      status: response.status,
      latency_ms: latency_ms,
      verdict: verdict,
      detected_protocols: detected,
      x402: x402,
      mpp: mpp,
      checks: checks,
      known_fix_ids: known_fix_ids,
      cors_expose: Map.get(headers, "access-control-expose-headers", []),
      cache_control: Map.get(headers, "cache-control", []),
      checked_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp normalize_headers(headers) when is_map(headers) do
    Map.new(headers, fn {k, v} ->
      {String.downcase(to_string(k)), List.wrap(v) |> Enum.map(&to_string/1)}
    end)
  end

  defp normalize_headers(headers) when is_list(headers) do
    Enum.reduce(headers, %{}, fn {k, v}, acc ->
      key = String.downcase(to_string(k))
      Map.update(acc, key, [to_string(v)], &[to_string(v) | &1])
    end)
  end

  defp inspect_x402(headers, parsed_body) do
    headers
    |> extract_x402_payload(parsed_body)
    |> format_x402_result()
  end

  defp extract_x402_payload(headers, parsed_body) do
    raw_header =
      List.first(Map.get(headers, "payment-required", [])) ||
        List.first(Map.get(headers, "x-payment-required", []))

    cond do
      is_binary(raw_header) -> decode_x402_header(raw_header)
      is_map(parsed_body) and is_list(parsed_body["accepts"]) -> {:ok, parsed_body, :body}
      true -> :none
    end
  end

  defp format_x402_result({:ok, payload, source}) do
    accepts = List.wrap(payload["accepts"])
    bazaar = get_in(payload, ["extensions", "bazaar"])

    %{
      present?: true,
      source: source,
      version: payload["x402Version"] || payload["version"],
      accepts_count: length(accepts),
      accepts: Enum.take(accepts, 5),
      bazaar_discoverable?: is_map(bazaar) and bazaar["discoverable"] == true,
      bazaar: bazaar
    }
  end

  defp format_x402_result({:error, reason}),
    do: %{present?: true, source: :header, parse_error: reason, accepts: []}

  defp format_x402_result(:none), do: %{present?: false, accepts: []}

  defp decode_x402_header(raw) do
    trimmed = String.trim(raw)

    case parse_json(trimmed) do
      %{} = map ->
        {:ok, map, :header_json}

      _not_json ->
        with {:ok, bytes} <- decode_b64_any(trimmed),
             %{} = map <- parse_json(bytes) do
          {:ok, map, :header_base64}
        else
          _ -> {:error, "PAYMENT-REQUIRED header is neither valid JSON nor base64 JSON."}
        end
    end
  end

  defp inspect_mpp(headers) do
    challenges =
      headers
      |> Map.get("www-authenticate", [])
      |> Enum.filter(&Regex.match?(~r/\APayment\b/i, String.trim(&1)))

    case challenges do
      [] ->
        %{present?: false, challenges: []}

      list ->
        parsed = Enum.map(list, &parse_mpp_challenge/1)
        %{present?: true, count: length(parsed), challenges: parsed}
    end
  end

  defp parse_mpp_challenge(header) do
    attrs =
      Regex.scan(~r/([a-zA-Z0-9_-]+)="([^"]*)"/, header)
      |> Map.new(fn [_, k, v] -> {String.downcase(k), v} end)

    decoded_request =
      case attrs["request"] do
        req when is_binary(req) and req != "" ->
          with {:ok, bytes} <- decode_b64_any(req),
               %{} = map <- parse_json(bytes) do
            map
          else
            _ -> %{"_error" => "Invalid base64url JSON in request parameter"}
          end

        _ ->
          nil
      end

    %{
      id: attrs["id"],
      realm: attrs["realm"],
      method: attrs["method"],
      intent: attrs["intent"],
      expires: attrs["expires"],
      request: decoded_request
    }
  end

  defp build_checks(status, headers, x402, mpp) do
    status_check =
      if status == 402 do
        %{level: :pass, code: "http_402", message: "Responded with HTTP 402 Payment Required."}
      else
        %{
          level: :fail,
          code: "not_402",
          message: "Expected HTTP 402 Payment Required for an unpaid probe, got HTTP #{status}."
        }
      end

    protocol_checks =
      x402_checks(x402, headers) ++
        mpp_checks(mpp, headers) ++
        dual_checks(x402, mpp)

    if protocol_checks == [] do
      [
        status_check,
        %{
          level: :fail,
          code: "no_payment_challenge",
          message:
            "Neither an x402 PAYMENT-REQUIRED header nor an MPP WWW-Authenticate: Payment header was detected."
        }
      ]
    else
      [status_check | protocol_checks]
    end
  end

  defp x402_checks(%{present?: false}, _headers), do: []

  defp x402_checks(%{parse_error: reason}, _headers),
    do: [%{level: :fail, code: "x402_malformed", message: reason}]

  defp x402_checks(x402, headers) do
    expose =
      headers
      |> Map.get("access-control-expose-headers", [])
      |> Enum.join(",")
      |> String.downcase()

    cors_check =
      if String.contains?(expose, "payment-required") do
        %{
          level: :pass,
          code: "x402_cors",
          message: "CORS exposes PAYMENT-REQUIRED for browser agents."
        }
      else
        %{
          level: :warn,
          code: "x402_cors_missing",
          message:
            "Access-Control-Expose-Headers does not list PAYMENT-REQUIRED (browser agents cannot read the 402 terms)."
        }
      end

    bazaar_check =
      if x402.bazaar_discoverable? do
        %{
          level: :pass,
          code: "bazaar_indexed",
          message: "Bazaar discovery extension (discoverable: true) is declared."
        }
      else
        %{
          level: :warn,
          code: "bazaar_missing",
          message:
            "No extensions.bazaar.discoverable metadata detected (recommended for agentic.market / Bazaar discovery)."
        }
      end

    accepts_check =
      if x402.accepts_count > 0 do
        %{
          level: :pass,
          code: "x402_accepts",
          message:
            "Valid x402 v#{x402.version || "?"} challenge with #{x402.accepts_count} payment option(s)."
        }
      else
        %{
          level: :fail,
          code: "x402_empty_accepts",
          message: "x402 challenge contains an empty accepts[] array."
        }
      end

    [accepts_check, cors_check, bazaar_check]
  end

  defp mpp_checks(%{present?: false}, _headers), do: []

  defp mpp_checks(%{challenges: challenges}, headers) do
    first = List.first(challenges) || %{}

    challenge_check =
      if is_binary(first[:method]) and is_binary(first[:intent]) and is_map(first[:request]) and
           not Map.has_key?(first[:request], "_error") do
        %{
          level: :pass,
          code: "mpp_valid",
          message:
            "Valid MPP WWW-Authenticate: Payment challenge (method=#{first[:method]}, intent=#{first[:intent]})."
        }
      else
        %{
          level: :fail,
          code: "mpp_malformed",
          message:
            "MPP WWW-Authenticate: Payment challenge is missing method, intent, or valid base64url JSON request payload."
        }
      end

    cache = headers |> Map.get("cache-control", []) |> Enum.join(",") |> String.downcase()

    cache_check =
      if String.contains?(cache, "no-store") do
        %{
          level: :pass,
          code: "mpp_cache_safe",
          message: "Cache-Control: no-store prevents CDN challenge caching."
        }
      else
        %{
          level: :warn,
          code: "mpp_cache_warn",
          message:
            "Recommend setting Cache-Control: no-store and Vary: Authorization on MPP 402 responses."
        }
      end

    [challenge_check, cache_check]
  end

  defp dual_checks(%{present?: true}, %{present?: true}) do
    [
      %{
        level: :pass,
        code: "dual_protocol",
        message: "Dual-rail HTTP 402 endpoint detected: advertises both x402 and MPP challenges."
      }
    ]
  end

  defp dual_checks(_x402, _mpp), do: []

  defp detected_protocols(x402, mpp) do
    []
    |> then(&if(x402.present?, do: ["x402" | &1], else: &1))
    |> then(&if(mpp.present?, do: ["mpp" | &1], else: &1))
    |> Enum.reverse()
  end

  defp suggested_known_fixes(status, headers, x402, mpp) do
    expose =
      headers
      |> Map.get("access-control-expose-headers", [])
      |> Enum.join(",")
      |> String.downcase()

    []
    |> then(fn list ->
      if x402.present? and
           (Map.has_key?(x402, :parse_error) or not String.contains?(expose, "payment-required")),
         do: ["x402-payment-required-cors" | list],
         else: list
    end)
    |> then(fn list ->
      if mpp.present?, do: ["mpp-tempo-www-authenticate-and-session" | list], else: list
    end)
    |> then(fn list ->
      if status == 402 and not x402.present? and not mpp.present?,
        do: ["x402-payment-required-cors", "mpp-tempo-www-authenticate-and-session" | list],
        else: list
    end)
    |> Enum.uniq()
  end

  defp decode_b64_any(str) do
    with :error <- Base.url_decode64(str, padding: false),
         :error <- Base.url_decode64(str),
         :error <- Base.decode64(str, padding: false) do
      Base.decode64(str)
    end
  end

  defp parse_json(raw) when is_binary(raw) do
    case Jason.decode(raw) do
      {:ok, value} -> value
      _ -> nil
    end
  end
end
