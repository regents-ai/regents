defmodule Regents.Patchbay.Probes.PaymentEndpoint do
  @moduledoc """
  SSRF-hardened live HTTP 402 + CORS preflight validator for Agentic Commerce
  endpoints.

  Probes an `https://` endpoint (unpaid `GET`/`POST`/`HEAD` + browser `OPTIONS`
  CORS preflight) and inspects:
  - **x402 v2**: `PAYMENT-REQUIRED` / `X-PAYMENT-REQUIRED` header decoding,
    `accepts[]` (`scheme`, CAIP-2 `network`, `asset`, `payTo`,
    `maxAmountRequired` / `amount`), `extensions.bazaar` discovery metadata,
    and browser CORS exposure + `OPTIONS` preflight headers.
  - **MPP (Machine Payments Protocol / Tempo / Stripe)**:
    `WWW-Authenticate: Payment` header parsing (`id`, `realm`, `method`, `intent`,
    `expires` ISO-8601 validity, base64url `request` JSON payload),
    `Cache-Control: no-store`, `Vary: Authorization`, and CORS exposure +
    `OPTIONS` preflight headers.
  - **Reproducible failure reporting**: attaches a prefilled `report_prefill`
    (redacted wire trace, failing check codes, and ready `/patchbay/forum` URL)
    so failed or degraded probes convert directly into reproducible Patchbay
    board reports.
  """

  alias RegentHttp.Public

  @allowed_methods ~w(GET POST HEAD)
  @max_url_bytes 512
  @max_body_bytes 32_768
  @timeout_ms 8_000
  @preflight_timeout_ms 5_000
  @caip2_pattern ~r/\A[a-z0-9-]+:[a-zA-Z0-9_-]+\z/

  @doc """
  Probe `url` using `method` (`"GET"`, `"POST"`, or `"HEAD"`), plus an `OPTIONS`
  CORS preflight check against the same URL.
  Returns `{:ok, diagnostic_map}` or `{:error, reason_string}`.
  """
  @spec probe(String.t(), String.t()) :: {:ok, map()} | {:error, String.t()}
  def probe(url, method \\ "GET")

  def probe(url, method) when is_binary(url) and is_binary(method) do
    normalized_method = method |> String.trim() |> String.upcase()
    trimmed_url = String.trim(url)

    with :ok <- validate_method(normalized_method),
         :ok <- validate_public_https_uri(trimmed_url),
         {:ok, %{response: response, latency_ms: latency_ms}} <-
           perform_request(trimmed_url, normalized_method) do
      preflight = perform_preflight(trimmed_url, normalized_method)

      {:ok,
       analyze_wire(%{
         url: trimmed_url,
         method: normalized_method,
         status: response.status,
         headers: response.headers,
         body: response.body || "",
         latency_ms: latency_ms,
         preflight: preflight
       })}
    end
  end

  def probe(_url, _method), do: {:error, "Provide a valid https:// URL and HTTP method."}

  @doc """
  Pure wire analyzer for deterministic conformance testing against frozen HTTP
  responses (unpaid response + optional `OPTIONS` preflight capture).
  """
  @spec analyze_wire(map()) :: map()
  def analyze_wire(
        %{
          url: url,
          method: method,
          status: status,
          headers: raw_headers,
          body: raw_body
        } = capture
      ) do
    now = Map.get(capture, :now) || DateTime.utc_now()
    latency_ms = Map.get(capture, :latency_ms, 0)
    headers = normalize_headers(raw_headers || %{})
    parsed_body = parse_json(raw_body || "")

    x402 = inspect_x402(headers, parsed_body)
    mpp = inspect_mpp(headers, now)
    detected = detected_protocols(x402, mpp)
    cors = inspect_cors(headers, Map.get(capture, :preflight), x402, mpp)
    checks = build_checks(status, headers, x402, mpp, cors)
    known_fix_ids = suggested_known_fixes(status, headers, x402, mpp, cors)
    verdict = compute_verdict(status, x402, mpp, checks)
    checked_at = DateTime.to_iso8601(now)

    result = %{
      url: url,
      method: method,
      status: status,
      latency_ms: latency_ms,
      verdict: verdict,
      detected_protocols: detected,
      x402: x402,
      mpp: mpp,
      cors: cors,
      checks: checks,
      known_fix_ids: known_fix_ids,
      cors_expose: Map.get(headers, "access-control-expose-headers", []),
      cache_control: Map.get(headers, "cache-control", []),
      checked_at: checked_at
    }

    Map.put(result, :report_prefill, build_report_prefill(result, headers))
  end

  # --- Request execution ---

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

  defp perform_preflight(url, method) do
    opts = [
      max_bytes: 4_096,
      timeout: @preflight_timeout_ms,
      headers: [
        {"origin", "https://regents.sh"},
        {"access-control-request-method", method},
        {"access-control-request-headers",
         "authorization, content-type, payment-signature, x-payment"},
        {"user-agent", "Patchbay-Validator/1.0 (+https://regents.sh/patchbay/validate)"}
      ]
    ]

    case Public.request(:options, url, opts) do
      {:ok, response} ->
        %{status: response.status, headers: response.headers}

      {:error, reason} ->
        %{status: nil, headers: %{}, error: to_string(reason)}
    end
  rescue
    _ -> %{status: nil, headers: %{}, error: "preflight_unsupported"}
  end

  # --- Header & protocol inspection ---

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
    invalid_accepts = Enum.flat_map(Enum.with_index(accepts), &validate_x402_accept/1)

    %{
      present?: true,
      source: source,
      version: payload["x402Version"] || payload["version"],
      accepts_count: length(accepts),
      accepts: Enum.take(accepts, 5),
      accepts_valid?: accepts != [] and invalid_accepts == [],
      accepts_errors: invalid_accepts,
      bazaar_discoverable?: is_map(bazaar) and bazaar["discoverable"] == true,
      bazaar: bazaar
    }
  end

  defp format_x402_result({:error, reason}),
    do: %{
      present?: true,
      source: :header,
      parse_error: reason,
      accepts: [],
      accepts_valid?: false
    }

  defp format_x402_result(:none), do: %{present?: false, accepts: [], accepts_valid?: false}

  defp validate_x402_accept({opt, idx}) when is_map(opt) do
    missing =
      []
      |> maybe_add_missing(opt["scheme"], "scheme")
      |> maybe_add_missing(opt["network"], "network")
      |> maybe_add_missing(opt["asset"], "asset")
      |> maybe_add_missing(opt["payTo"], "payTo")
      |> maybe_add_missing(opt["maxAmountRequired"] || opt["amount"], "amount/maxAmountRequired")

    network_err =
      if is_binary(opt["network"]) and not Regex.match?(@caip2_pattern, opt["network"]) and
           opt["network"] not in ["base", "base-sepolia", "solana", "solana-devnet"] do
        ["accepts[#{idx}].network '#{opt["network"]}' is not a valid CAIP-2 chain id"]
      else
        []
      end

    missing_err =
      if missing == [],
        do: [],
        else: ["accepts[#{idx}] missing #{Enum.join(Enum.reverse(missing), ", ")}"]

    missing_err ++ network_err
  end

  defp validate_x402_accept({_other, idx}), do: ["accepts[#{idx}] is not a JSON object"]

  defp maybe_add_missing(acc, val, _label) when is_binary(val) and val != "", do: acc
  defp maybe_add_missing(acc, val, _label) when is_integer(val) and val > 0, do: acc
  defp maybe_add_missing(acc, _val, label), do: [label | acc]

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

  defp inspect_mpp(headers, now) do
    challenges =
      headers
      |> Map.get("www-authenticate", [])
      |> Enum.filter(&Regex.match?(~r/\APayment\b/i, String.trim(&1)))

    case challenges do
      [] ->
        %{present?: false, challenges: [], valid?: false}

      list ->
        parsed = Enum.map(list, &parse_mpp_challenge(&1, now))
        valid? = Enum.any?(parsed, & &1.valid?)
        %{present?: true, count: length(parsed), valid?: valid?, challenges: parsed}
    end
  end

  defp parse_mpp_challenge(header, now) do
    attrs =
      Regex.scan(~r/([a-zA-Z0-9_-]+)="([^"]*)"/, header)
      |> Map.new(fn [_, k, v] -> {String.downcase(k), v} end)

    decoded_request = decode_mpp_request(attrs["request"])
    expires_state = check_expires(attrs["expires"], now)
    errors = mpp_challenge_errors(attrs, decoded_request, expires_state)

    %{
      id: attrs["id"],
      realm: attrs["realm"],
      method: attrs["method"],
      intent: attrs["intent"],
      expires: attrs["expires"],
      expires_state: expires_state,
      request: decoded_request,
      valid?: errors == [],
      errors: errors
    }
  end

  defp decode_mpp_request(req) when is_binary(req) and req != "" do
    with {:ok, bytes} <- decode_b64_any(req),
         %{} = map <- parse_json(bytes) do
      map
    else
      _ -> %{"_error" => "Invalid base64url JSON in request parameter"}
    end
  end

  defp decode_mpp_request(_other), do: nil

  defp mpp_challenge_errors(attrs, decoded_request, expires_state) do
    valid_request? = is_map(decoded_request) and not Map.has_key?(decoded_request, "_error")

    []
    |> maybe_add_mpp_err(blank?(attrs["id"]), "missing id")
    |> maybe_add_mpp_err(blank?(attrs["method"]), "missing method")
    |> maybe_add_mpp_err(
      attrs["intent"] not in ["charge", "session"],
      "intent must be 'charge' or 'session'"
    )
    |> maybe_add_mpp_err(not valid_request?, "invalid base64url JSON request payload")
    |> maybe_add_mpp_err(
      valid_request? and
        (is_nil(decoded_request["amount"]) or is_nil(decoded_request["currency"])),
      "request payload missing amount or currency"
    )
    |> maybe_add_mpp_err(expires_state == :invalid, "expires is not valid ISO-8601")
    |> maybe_add_mpp_err(expires_state == :expired, "challenge expires timestamp is in the past")
    |> Enum.reverse()
  end

  defp blank?(val), do: not is_binary(val) or val == ""

  defp maybe_add_mpp_err(acc, true, msg), do: [msg | acc]
  defp maybe_add_mpp_err(acc, false, _msg), do: acc

  defp check_expires(nil, _now), do: :absent
  defp check_expires("", _now), do: :absent

  defp check_expires(raw, now) when is_binary(raw) do
    case DateTime.from_iso8601(raw) do
      {:ok, dt, _offset} ->
        if DateTime.compare(dt, now) == :gt, do: :future, else: :expired

      {:error, _} ->
        :invalid
    end
  end

  defp inspect_cors(headers, preflight, x402, mpp) do
    expose = joined_header(headers, "access-control-expose-headers")
    resp_allow_origin = List.first(Map.get(headers, "access-control-allow-origin", []))
    pf_status = preflight && preflight[:status]
    pf_headers = normalize_headers((preflight && preflight[:headers]) || %{})
    pf_allow_origin = List.first(Map.get(pf_headers, "access-control-allow-origin", []))
    pf_allow_headers = joined_header(pf_headers, "access-control-allow-headers")

    %{
      tested?: not is_nil(preflight),
      preflight_status: pf_status,
      preflight_ok:
        evaluate_preflight_ok(preflight, pf_status, pf_allow_origin, pf_allow_headers, x402, mpp),
      preflight_error: preflight && preflight[:error],
      allow_origin: pf_allow_origin || resp_allow_origin,
      allow_headers: Map.get(pf_headers, "access-control-allow-headers", []),
      expose_headers: Map.get(headers, "access-control-expose-headers", []),
      x402_exposed?: String.contains?(expose, "payment-required"),
      mpp_exposed?: String.contains?(expose, "www-authenticate")
    }
  end

  defp joined_header(headers, key) do
    headers |> Map.get(key, []) |> Enum.join(",") |> String.downcase()
  end

  defp evaluate_preflight_ok(nil, _status, _origin, _headers, _x402, _mpp), do: nil

  defp evaluate_preflight_ok(_preflight, status, origin, allow_headers, x402, mpp) do
    status in [200, 204] and preflight_origin_ok?(origin) and
      preflight_headers_ok?(allow_headers, x402, mpp)
  end

  defp preflight_origin_ok?(origin) when is_binary(origin),
    do: origin == "*" or String.contains?(origin, "regents.sh")

  defp preflight_origin_ok?(_other), do: false

  defp preflight_headers_ok?(allow_headers, x402, mpp) do
    wildcard? = String.contains?(allow_headers, "*")

    x402_ok? =
      not x402.present? or wildcard? or
        String.contains?(allow_headers, "payment-signature") or
        String.contains?(allow_headers, "x-payment")

    mpp_ok? = not mpp.present? or wildcard? or String.contains?(allow_headers, "authorization")
    x402_ok? and mpp_ok?
  end

  # --- Checks & verdict ---

  defp build_checks(status, headers, x402, mpp, cors) do
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
      x402_checks(x402, cors) ++
        mpp_checks(mpp, headers, cors) ++
        dual_checks(x402, mpp) ++
        preflight_checks(cors, x402, mpp)

    if not x402.present? and not mpp.present? do
      [
        status_check,
        %{
          level: :fail,
          code: "no_payment_challenge",
          message:
            "Neither an x402 PAYMENT-REQUIRED header nor an MPP WWW-Authenticate: Payment header was detected."
        }
      ] ++ preflight_checks(cors, x402, mpp)
    else
      [status_check | protocol_checks]
    end
  end

  defp x402_checks(%{present?: false}, _cors), do: []

  defp x402_checks(%{parse_error: reason}, _cors),
    do: [%{level: :fail, code: "x402_malformed", message: reason}]

  defp x402_checks(x402, cors) do
    accepts_check =
      cond do
        x402.accepts_count == 0 ->
          %{
            level: :fail,
            code: "x402_empty_accepts",
            message: "x402 challenge contains an empty accepts[] array."
          }

        not x402.accepts_valid? ->
          %{
            level: :fail,
            code: "x402_accepts_invalid",
            message: "x402 accepts[] schema issues: #{Enum.join(x402.accepts_errors, "; ")}."
          }

        true ->
          %{
            level: :pass,
            code: "x402_accepts",
            message:
              "Valid x402 v#{x402.version || "?"} challenge with #{x402.accepts_count} spec-compliant payment option(s)."
          }
      end

    cors_check =
      if cors.x402_exposed? do
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

    [accepts_check, cors_check, bazaar_check]
  end

  defp mpp_checks(%{present?: false}, _headers, _cors), do: []

  defp mpp_checks(%{challenges: challenges}, headers, cors) do
    first = List.first(challenges) || %{}

    challenge_check =
      if first[:valid?] do
        %{
          level: :pass,
          code: "mpp_valid",
          message:
            "Valid MPP WWW-Authenticate: Payment challenge (method=#{first[:method]}, intent=#{first[:intent]})."
        }
      else
        detail =
          case first[:errors] do
            [_ | _] = errs -> Enum.join(errs, "; ")
            _ -> "missing id, method, intent, or valid base64url JSON request payload"
          end

        %{
          level: :fail,
          code: "mpp_malformed",
          message: "MPP WWW-Authenticate: Payment challenge invalid: #{detail}."
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
            "Recommend setting Cache-Control: no-store on MPP 402 responses to avoid stale challenges."
        }
      end

    vary = headers |> Map.get("vary", []) |> Enum.join(",") |> String.downcase()

    vary_check =
      if String.contains?(vary, "authorization") do
        %{
          level: :pass,
          code: "mpp_vary_auth",
          message: "Vary: Authorization separates unpaid 402 challenges from paid retries."
        }
      else
        %{
          level: :warn,
          code: "mpp_vary_missing",
          message: "Recommend setting Vary: Authorization on MPP 402 responses."
        }
      end

    expose_check =
      if cors.mpp_exposed? do
        %{
          level: :pass,
          code: "mpp_cors_expose",
          message: "CORS exposes WWW-Authenticate for browser/WebMCP agents."
        }
      else
        %{
          level: :warn,
          code: "mpp_cors_missing",
          message:
            "Access-Control-Expose-Headers does not list WWW-Authenticate (browser agents cannot read the MPP challenge)."
        }
      end

    [challenge_check, cache_check, vary_check, expose_check]
  end

  defp preflight_checks(%{tested?: false}, _x402, _mpp), do: []

  defp preflight_checks(%{preflight_ok: true, preflight_status: status}, _x402, _mpp) do
    [
      %{
        level: :pass,
        code: "cors_preflight_ok",
        message:
          "CORS OPTIONS preflight passed (HTTP #{status}) and permits payment authorization headers."
      }
    ]
  end

  defp preflight_checks(%{preflight_ok: false, preflight_status: status} = cors, x402, mpp) do
    needed =
      []
      |> then(&if(x402.present?, do: ["Payment-Signature" | &1], else: &1))
      |> then(&if(mpp.present?, do: ["Authorization" | &1], else: &1))
      |> case do
        [] -> "Authorization / Payment-Signature"
        list -> Enum.join(list, ", ")
      end

    detail =
      cond do
        is_nil(status) ->
          "CORS OPTIONS preflight could not complete (#{cors.preflight_error || "error"})."

        status not in [200, 204] ->
          "CORS OPTIONS preflight returned HTTP #{status} instead of 200/204; browser/WebMCP agents cannot send #{needed}."

        true ->
          "CORS OPTIONS preflight (HTTP #{status}) does not allow Origin and #{needed} in Access-Control-Allow-Headers."
      end

    [%{level: :warn, code: "cors_preflight_failed", message: detail}]
  end

  defp preflight_checks(_cors, _x402, _mpp), do: []

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

  defp compute_verdict(status, x402, mpp, checks) do
    valid? = valid_protocol?(x402, mpp)
    any_fail? = Enum.any?(checks, &(&1.level == :fail))

    cond do
      status == 402 and valid? and not any_fail? -> :pass
      status == 402 and valid? -> :warn
      true -> :fail
    end
  end

  defp valid_protocol?(x402, mpp),
    do:
      (x402.present? and x402[:accepts_valid?] == true) or (mpp.present? and mpp[:valid?] == true)

  defp detected_protocols(x402, mpp) do
    []
    |> then(&if(x402.present?, do: ["x402" | &1], else: &1))
    |> then(&if(mpp.present?, do: ["mpp" | &1], else: &1))
    |> Enum.reverse()
  end

  defp suggested_known_fixes(status, _headers, x402, mpp, cors) do
    []
    |> maybe_prepend(x402_needs_fix?(x402, cors), ["x402-payment-required-cors"])
    |> maybe_prepend(mpp.present?, ["mpp-tempo-www-authenticate-and-session"])
    |> maybe_prepend(
      status == 402 and not x402.present? and not mpp.present?,
      ["x402-payment-required-cors", "mpp-tempo-www-authenticate-and-session"]
    )
    |> Enum.uniq()
  end

  defp x402_needs_fix?(x402, cors) do
    x402.present? and
      (Map.has_key?(x402, :parse_error) or not x402.accepts_valid? or not cors.x402_exposed? or
         cors.preflight_ok == false)
  end

  defp maybe_prepend(list, true, items), do: items ++ list
  defp maybe_prepend(list, false, _items), do: list

  # --- Reproducible bug report prefill ---

  defp build_report_prefill(result, headers) do
    uri = URI.parse(result.url)
    host = uri.host || result.url
    path = uri.path || "/"

    failing = Enum.filter(result.checks, &(&1.level == :fail))
    warnings = Enum.filter(result.checks, &(&1.level == :warn))

    headline =
      cond do
        result.status != 402 ->
          "#{result.method} #{host}#{path} returned HTTP #{result.status} instead of 402"

        failing != [] ->
          codes = Enum.map_join(failing, ", ", & &1.code)
          "HTTP 402 validation failed on #{host}#{path} (#{codes})"

        warnings != [] ->
          codes = Enum.map_join(warnings, ", ", & &1.code)
          "HTTP 402 compatibility warning on #{host}#{path} (#{codes})"

        true ->
          "HTTP 402 validation note for #{host}#{path}"
      end
      |> String.slice(0, 155)

    tags =
      (result.detected_protocols ++ ["http-402"])
      |> Enum.uniq()
      |> Enum.join(",")

    wire_lines =
      [
        "### Reproducible Wire Probe (`#{result.checked_at}`)",
        "- Request: `#{result.method} #{result.url}`",
        "- Response: `HTTP #{result.status}` (`#{result.latency_ms}ms`)",
        "- Verdict: `#{result.verdict}` · Detected protocols: `#{Enum.join(result.detected_protocols, ", ")}`",
        if(result.cors.tested?,
          do:
            "- CORS `OPTIONS` preflight: `HTTP #{result.cors.preflight_status || "error"}` (`preflight_ok=#{result.cors.preflight_ok}`)"
        ),
        header_summary_line("WWW-Authenticate", headers["www-authenticate"]),
        header_summary_line("PAYMENT-REQUIRED", headers["payment-required"]),
        header_summary_line(
          "Access-Control-Allow-Origin",
          headers["access-control-allow-origin"]
        ),
        header_summary_line(
          "Access-Control-Expose-Headers",
          headers["access-control-expose-headers"]
        ),
        header_summary_line("Cache-Control", headers["cache-control"]),
        "",
        "### Diagnostic Checks"
      ]
      |> Enum.reject(&is_nil/1)

    check_lines =
      Enum.map(result.checks, fn chk ->
        "- **[#{String.upcase(to_string(chk.level))}]** `#{chk.code}`: #{chk.message}"
      end)

    body_markdown = Enum.join(wire_lines ++ check_lines, "\n")

    query =
      URI.encode_query(%{
        "ask" => "1",
        "site_url" => result.url,
        "goal" => headline,
        "details" => body_markdown,
        "topic_tags" => tags
      })

    %{
      site: host,
      title: headline,
      topic_tags: tags,
      body_markdown: body_markdown,
      forum_url: "/patchbay/forum?#{query}#pb-hero"
    }
  end

  defp header_summary_line(_label, nil), do: nil
  defp header_summary_line(_label, []), do: nil

  defp header_summary_line(label, values) do
    joined = values |> Enum.join(", ") |> String.slice(0, 220)
    "- `#{label}`: `#{joined}`"
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
