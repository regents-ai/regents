defmodule Regents.Patchbay.Probes.PaymentEndpoint do
  @moduledoc """
  SSRF-hardened live HTTP 402 + CORS preflight validator for Agentic Commerce
  endpoints.

  Probes an `https://` endpoint (unpaid `GET`/`POST`/`HEAD` with optional
  request body + browser `OPTIONS` CORS preflight) and inspects:
  - **x402 v2**: `PAYMENT-REQUIRED` / `X-PAYMENT-REQUIRED` header decoding,
    `accepts[]` (`scheme`, CAIP-2 `network`, `asset`, `payTo` address format +
    burn-address guard, `maxAmountRequired` / `amount` unit sanity,
    `maxTimeoutSeconds`), `extensions.bazaar` discovery metadata (both x402 v2
    `info`/`schema` and legacy `discoverable: true`), and browser CORS exposure
    + `OPTIONS` preflight headers.
  - **MPP (Machine Payments Protocol / Tempo / Stripe)**:
    `WWW-Authenticate: Payment` header parsing (`id`, `realm`, `method`, `intent`,
    `expires` ISO-8601 validity + TTL remaining, base64url `request` JSON payload,
    recipient format), `Cache-Control: no-store`, `Vary: Authorization`, and CORS
    exposure + `OPTIONS` preflight headers.
  - **Cross-rail & transport traps**: HTTP `3xx` redirect detection (which strips
    `Authorization` / `Payment-Signature` headers), dual-rail price parity checks
    when an endpoint advertises both x402 and MPP, and decoded human-readable
    pricing summaries.
  - **Reproducible failure reporting**: attaches a prefilled `report_prefill`
    (redacted wire trace, failing check codes, and ready `/patchbay/forum` URL)
    so failed or degraded probes convert directly into reproducible Patchbay
    board reports.
  """

  alias RegentHttp.Public

  @allowed_methods ~w(GET POST HEAD)
  @max_url_bytes 512
  @max_req_body_bytes 16_384
  @max_body_bytes 32_768
  @timeout_ms 8_000
  @preflight_timeout_ms 5_000
  @min_safe_timeout_seconds 15
  @max_sane_usd 100.0
  @dual_price_tolerance 0.05
  @caip2_pattern ~r/\A[a-z0-9-]+:[a-zA-Z0-9_-]+\z/
  @evm_addr_pattern ~r/\A0x[0-9a-fA-F]{40}\z/
  @zero_evm_address "0x0000000000000000000000000000000000000000"
  @solana_addr_pattern ~r/\A[1-9A-HJ-NP-Za-km-z]{32,44}\z/

  @known_networks %{
    "eip155:8453" => "Base Mainnet",
    "eip155:84532" => "Base Sepolia",
    "eip155:4217" => "Tempo Mainnet",
    "eip155:1" => "Ethereum Mainnet",
    "eip155:10" => "Optimism",
    "eip155:42161" => "Arbitrum One",
    "eip155:137" => "Polygon",
    "base" => "Base Mainnet",
    "base-sepolia" => "Base Sepolia",
    "solana:5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp" => "Solana Mainnet",
    "solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1" => "Solana Devnet",
    "solana" => "Solana Mainnet",
    "solana-devnet" => "Solana Devnet"
  }

  @six_decimal_assets MapSet.new([
                        "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913",
                        "0x036cbd53842c5426634e7929541ec2318f3dcf7e",
                        "0x20c000000000000000000000b9537d11c60e8b50",
                        "0x20c0000000000000000000000000000000000000",
                        "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
                        "epjfwdd5aufqssqem2qn1xzybapc8g4weggkzwytdt1v",
                        "usdc",
                        "usdc.e",
                        "pathusd",
                        "usdt"
                      ])

  @doc """
  Probe `url` using `method` (`"GET"`, `"POST"`, or `"HEAD"`), with optional
  `opts` (`[body: json_or_text_string]`), plus an `OPTIONS` CORS preflight check
  against the same URL. Returns `{:ok, diagnostic_map}` or `{:error, reason_string}`.
  """
  @spec probe(String.t(), String.t(), keyword() | String.t() | nil) ::
          {:ok, map()} | {:error, String.t()}
  def probe(url, method \\ "GET", opts \\ [])

  def probe(url, method, opts) when is_binary(url) and is_binary(method) do
    normalized_method = method |> String.trim() |> String.upcase()
    trimmed_url = String.trim(url)
    req_body = extract_request_body(opts)

    with :ok <- validate_method(normalized_method),
         :ok <- validate_public_https_uri(trimmed_url),
         :ok <- validate_request_body(req_body),
         {:ok, %{response: response, latency_ms: latency_ms}} <-
           perform_request(trimmed_url, normalized_method, req_body) do
      preflight = perform_preflight(trimmed_url, normalized_method)

      {:ok,
       analyze_wire(%{
         url: trimmed_url,
         method: normalized_method,
         status: response.status,
         headers: response.headers,
         body: response.body || "",
         latency_ms: latency_ms,
         preflight: preflight,
         request_body_sent?: is_binary(req_body) and req_body != ""
       })}
    end
  end

  def probe(_url, _method, _opts),
    do: {:error, "Provide a valid https:// URL and HTTP method."}

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
    pricing = build_pricing_summary(x402, mpp)
    checks = build_checks(status, headers, x402, mpp, cors, pricing)
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
      pricing: pricing,
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

  defp extract_request_body(opts) when is_list(opts), do: Keyword.get(opts, :body)
  defp extract_request_body(body) when is_binary(body), do: body
  defp extract_request_body(_other), do: nil

  defp validate_request_body(nil), do: :ok

  defp validate_request_body(body)
       when is_binary(body) and byte_size(body) <= @max_req_body_bytes,
       do: :ok

  defp validate_request_body(_body),
    do: {:error, "Request body exceeds #{@max_req_body_bytes} bytes."}

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

  defp perform_request(url, method, req_body) do
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
        {"user-agent", "Patchbay-Validator/1.1 (+https://regents.sh/patchbay/validate)"}
      ]
    ]

    opts = maybe_attach_post_body(opts, req_method, req_body)
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

  defp maybe_attach_post_body(opts, :post, req_body) do
    payload = if is_binary(req_body) and String.trim(req_body) != "", do: req_body, else: "{}"

    Keyword.merge(opts,
      body: payload,
      headers: [{"content-type", "application/json"} | opts[:headers]]
    )
  end

  defp maybe_attach_post_body(opts, _method, _req_body), do: opts

  defp perform_preflight(url, method) do
    opts = [
      max_bytes: 4_096,
      timeout: @preflight_timeout_ms,
      headers: [
        {"origin", "https://regents.sh"},
        {"access-control-request-method", method},
        {"access-control-request-headers",
         "authorization, content-type, payment-signature, x-payment"},
        {"user-agent", "Patchbay-Validator/1.1 (+https://regents.sh/patchbay/validate)"}
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
    bazaar_format = classify_bazaar(bazaar)

    %{
      present?: true,
      source: source,
      version: payload["x402Version"] || payload["version"],
      accepts_count: length(accepts),
      accepts: Enum.take(accepts, 5),
      accepts_valid?: accepts != [] and invalid_accepts == [],
      accepts_errors: invalid_accepts,
      bazaar_discoverable?: bazaar_format != nil,
      bazaar_format: bazaar_format,
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

  defp classify_bazaar(%{"info" => info, "schema" => schema})
       when is_map(info) and is_map(schema),
       do: :v2_schema

  defp classify_bazaar(%{"discoverable" => true}), do: :legacy_flag
  defp classify_bazaar(_other), do: nil

  defp validate_x402_accept({opt, idx}) when is_map(opt) do
    missing =
      []
      |> maybe_add_missing(opt["scheme"], "scheme")
      |> maybe_add_missing(opt["network"], "network")
      |> maybe_add_missing(opt["asset"], "asset")
      |> maybe_add_missing(opt["payTo"], "payTo")
      |> maybe_add_missing(opt["maxAmountRequired"] || opt["amount"], "amount/maxAmountRequired")

    missing_err =
      if missing == [],
        do: [],
        else: ["accepts[#{idx}] missing #{Enum.join(Enum.reverse(missing), ", ")}"]

    missing_err ++ network_error(opt["network"], idx)
  end

  defp validate_x402_accept({_other, idx}), do: ["accepts[#{idx}] is not a JSON object"]

  defp network_error(network, idx) when is_binary(network) do
    if Regex.match?(@caip2_pattern, network) or
         network in ["base", "base-sepolia", "solana", "solana-devnet"] do
      []
    else
      ["accepts[#{idx}].network '#{network}' is not a valid CAIP-2 chain id"]
    end
  end

  defp network_error(_network, _idx), do: []

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
    {expires_state, ttl_seconds} = check_expires(attrs["expires"], now)
    errors = mpp_challenge_errors(attrs, decoded_request, expires_state)

    %{
      id: attrs["id"],
      realm: attrs["realm"],
      method: attrs["method"],
      intent: attrs["intent"],
      expires: attrs["expires"],
      expires_state: expires_state,
      ttl_seconds: ttl_seconds,
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

  defp check_expires(nil, _now), do: {:absent, nil}
  defp check_expires("", _now), do: {:absent, nil}

  defp check_expires(raw, now) when is_binary(raw) do
    case DateTime.from_iso8601(raw) do
      {:ok, dt, _offset} ->
        diff = DateTime.diff(dt, now, :second)
        if diff > 0, do: {:future, diff}, else: {:expired, diff}

      {:error, _} ->
        {:invalid, nil}
    end
  end

  # --- Decoded pricing & recipient validation ---

  defp build_pricing_summary(x402, mpp) do
    %{
      x402: decode_x402_pricing(x402),
      mpp: decode_mpp_pricing(mpp)
    }
  end

  defp decode_x402_pricing(%{present?: true, accepts: [first | _]}) when is_map(first) do
    network = first["network"]
    asset = first["asset"]
    raw_amount = first["maxAmountRequired"] || first["amount"]
    recipient = first["payTo"]
    currency = infer_asset_symbol(asset, first["extra"])
    atomic = parse_atomic_int(raw_amount)
    usd = atomic_to_usd(atomic, asset, currency)

    %{
      rail_label: Map.get(@known_networks, network, network || "unknown"),
      network: network,
      asset: asset,
      currency: currency,
      raw_amount: raw_amount,
      atomic_amount: atomic,
      usd_amount: usd,
      amount_display: format_amount_display(usd, currency, raw_amount),
      recipient: recipient,
      recipient_status: validate_recipient(recipient, network),
      timeout_seconds: parse_optional_int(first["maxTimeoutSeconds"])
    }
  end

  defp decode_x402_pricing(_other), do: nil

  defp decode_mpp_pricing(%{present?: true, challenges: [first | _]}) when is_map(first) do
    req = if is_map(first[:request]), do: first[:request], else: %{}
    method = first[:method]
    network = req["network"] || default_mpp_network(method)
    currency_raw = req["currency"]
    currency = infer_asset_symbol(currency_raw, nil)
    raw_amount = req["amount"]
    atomic = parse_atomic_int(raw_amount)
    usd = mpp_to_usd(atomic, raw_amount, currency_raw, currency)
    recipient = req["recipient"] || req["payTo"]

    %{
      rail_label: mpp_rail_label(method, network),
      network: network,
      method: method,
      intent: first[:intent],
      currency: currency,
      raw_amount: raw_amount,
      atomic_amount: atomic,
      usd_amount: usd,
      amount_display: format_amount_display(usd, currency, raw_amount),
      recipient: recipient,
      recipient_status: validate_mpp_recipient(recipient, network, method),
      ttl_seconds: first[:ttl_seconds]
    }
  end

  defp decode_mpp_pricing(_other), do: nil

  defp default_mpp_network("tempo"), do: "eip155:4217"
  defp default_mpp_network(_method), do: nil

  defp mpp_rail_label("tempo", network),
    do: "Tempo (#{Map.get(@known_networks, network, network || "eip155:4217")})"

  defp mpp_rail_label(method, _network) when is_binary(method),
    do: "MPP (#{String.capitalize(method)})"

  defp mpp_rail_label(_method, _network), do: "MPP"

  defp infer_asset_symbol(asset, extra) when is_binary(asset) do
    lower = String.downcase(String.trim(asset))

    cond do
      lower in [
        "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913",
        "0x036cbd53842c5426634e7929541ec2318f3dcf7e",
        "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
        "epjfwdd5aufqssqem2qn1xzybapc8g4weggkzwytdt1v"
      ] ->
        "USDC"

      lower == "0x20c000000000000000000000b9537d11c60e8b50" ->
        "USDC.e"

      lower == "0x20c0000000000000000000000000000000000000" ->
        "pathUSD"

      is_map(extra) and is_binary(extra["name"]) and String.contains?(extra["name"], "USD") ->
        "USDC"

      byte_size(asset) <= 12 ->
        asset

      true ->
        "TOKEN"
    end
  end

  defp infer_asset_symbol(_asset, _extra), do: "TOKEN"

  defp parse_atomic_int(val) when is_integer(val), do: val

  defp parse_atomic_int(val) when is_binary(val) do
    case Integer.parse(String.trim(val)) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp parse_atomic_int(_val), do: nil

  defp parse_optional_int(val) when is_integer(val), do: val

  defp parse_optional_int(val) when is_binary(val) do
    case Integer.parse(String.trim(val)) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp parse_optional_int(_val), do: nil

  defp atomic_to_usd(atomic, asset, currency) when is_integer(atomic) do
    key_asset = if is_binary(asset), do: String.downcase(String.trim(asset)), else: ""
    key_curr = if is_binary(currency), do: String.downcase(String.trim(currency)), else: ""

    if MapSet.member?(@six_decimal_assets, key_asset) or
         MapSet.member?(@six_decimal_assets, key_curr) do
      Float.round(atomic / 1_000_000, 6)
    else
      nil
    end
  end

  defp atomic_to_usd(_atomic, _asset, _currency), do: nil

  defp mpp_to_usd(atomic, raw_amount, currency_raw, currency) do
    cond do
      is_integer(atomic) and String.downcase(to_string(currency_raw || "")) == "usd" ->
        Float.round(atomic / 100, 4)

      is_integer(atomic) ->
        atomic_to_usd(atomic, currency_raw, currency)

      is_binary(raw_amount) ->
        parse_decimal_usd(raw_amount)

      true ->
        nil
    end
  end

  defp parse_decimal_usd(raw) do
    case Float.parse(String.trim(raw)) do
      {f, ""} -> Float.round(f, 6)
      _ -> nil
    end
  end

  defp format_amount_display(usd, currency, _raw) when is_number(usd) do
    formatted =
      if usd < 0.01 and usd > 0,
        do: :erlang.float_to_binary(usd / 1, decimals: 4),
        else: :erlang.float_to_binary(usd / 1, decimals: 2)

    "$#{formatted} #{currency}"
  end

  defp format_amount_display(_usd, currency, raw) when not is_nil(raw),
    do: "#{raw} #{currency}"

  defp format_amount_display(_usd, _currency, _raw), do: nil

  defp validate_recipient(addr, network) when is_binary(addr) and is_binary(network) do
    trimmed = String.trim(addr)

    cond do
      evm_network?(network) -> validate_evm_address(trimmed)
      solana_network?(network) -> validate_solana_address(trimmed)
      trimmed == "" -> :missing
      true -> :ok
    end
  end

  defp validate_recipient(nil, _network), do: :missing
  defp validate_recipient("", _network), do: :missing
  defp validate_recipient(_addr, _network), do: :ok

  defp validate_mpp_recipient(nil, _network, _method), do: :absent
  defp validate_mpp_recipient("", _network, _method), do: :absent

  defp validate_mpp_recipient(addr, network, "tempo"),
    do: validate_recipient(addr, network || "eip155:4217")

  defp validate_mpp_recipient(_addr, _network, _method), do: :ok

  defp evm_network?(net),
    do: String.starts_with?(net, "eip155:") or net in ["base", "base-sepolia"]

  defp solana_network?(net),
    do: String.starts_with?(net, "solana:") or net in ["solana", "solana-devnet"]

  defp validate_evm_address(addr) do
    cond do
      not Regex.match?(@evm_addr_pattern, addr) -> :malformed
      String.downcase(addr) == @zero_evm_address -> :burn_address
      true -> :ok
    end
  end

  defp validate_solana_address(addr) do
    if Regex.match?(@solana_addr_pattern, addr), do: :ok, else: :malformed
  end

  # --- CORS inspection ---

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

  defp build_checks(status, headers, x402, mpp, cors, pricing) do
    status_checks = status_checks(status, headers)

    protocol_checks =
      x402_checks(x402, cors, pricing.x402) ++
        mpp_checks(mpp, headers, cors, pricing.mpp) ++
        dual_checks(x402, mpp, pricing) ++
        preflight_checks(cors, x402, mpp)

    if not x402.present? and not mpp.present? do
      status_checks ++
        [
          %{
            level: :fail,
            code: "no_payment_challenge",
            message:
              "Neither an x402 PAYMENT-REQUIRED header nor an MPP WWW-Authenticate: Payment header was detected."
          }
        ] ++ preflight_checks(cors, x402, mpp)
    else
      status_checks ++ protocol_checks
    end
  end

  defp status_checks(402, _headers) do
    [%{level: :pass, code: "http_402", message: "Responded with HTTP 402 Payment Required."}]
  end

  defp status_checks(status, headers) when status in [301, 302, 303, 307, 308] do
    location = List.first(Map.get(headers, "location", []))
    target = if is_binary(location) and location != "", do: " to #{location}", else: ""

    [
      %{
        level: :fail,
        code: "redirect_drops_payment_headers",
        message:
          "Responded with HTTP #{status} redirect#{target}. HTTP clients strip Authorization and Payment-Signature headers across redirects—serve the HTTP 402 directly from the canonical URL."
      }
    ]
  end

  defp status_checks(status, _headers) do
    [
      %{
        level: :fail,
        code: "not_402",
        message: "Expected HTTP 402 Payment Required for an unpaid probe, got HTTP #{status}."
      }
    ]
  end

  defp x402_checks(%{present?: false}, _cors, _pricing), do: []

  defp x402_checks(%{parse_error: reason}, _cors, _pricing),
    do: [%{level: :fail, code: "x402_malformed", message: reason}]

  defp x402_checks(x402, cors, x402_pricing) do
    [
      x402_accepts_check(x402),
      x402_cors_check(cors),
      x402_bazaar_check(x402)
    ] ++
      recipient_checks(x402_pricing, "x402 payTo") ++
      price_sanity_checks(x402_pricing, "x402") ++
      timeout_checks(x402_pricing && x402_pricing.timeout_seconds, "x402 maxTimeoutSeconds")
  end

  defp x402_accepts_check(%{accepts_count: 0}) do
    %{
      level: :fail,
      code: "x402_empty_accepts",
      message: "x402 challenge contains an empty accepts[] array."
    }
  end

  defp x402_accepts_check(%{accepts_valid?: false, accepts_errors: errs}) do
    %{
      level: :fail,
      code: "x402_accepts_invalid",
      message: "x402 accepts[] schema issues: #{Enum.join(errs, "; ")}."
    }
  end

  defp x402_accepts_check(x402) do
    %{
      level: :pass,
      code: "x402_accepts",
      message:
        "Valid x402 v#{x402.version || "?"} challenge with #{x402.accepts_count} spec-compliant payment option(s)."
    }
  end

  defp x402_cors_check(%{x402_exposed?: true}) do
    %{
      level: :pass,
      code: "x402_cors",
      message: "CORS exposes PAYMENT-REQUIRED for browser agents."
    }
  end

  defp x402_cors_check(_cors) do
    %{
      level: :warn,
      code: "x402_cors_missing",
      message:
        "Access-Control-Expose-Headers does not list PAYMENT-REQUIRED (browser agents cannot read the 402 terms)."
    }
  end

  defp x402_bazaar_check(%{bazaar_format: :v2_schema}) do
    %{
      level: :pass,
      code: "bazaar_indexed",
      message:
        "x402 v2 Bazaar discovery schema (extensions.bazaar info + JSON Schema) is declared."
    }
  end

  defp x402_bazaar_check(%{bazaar_format: :legacy_flag}) do
    %{
      level: :pass,
      code: "bazaar_indexed",
      message: "Bazaar discovery extension (discoverable: true) is declared."
    }
  end

  defp x402_bazaar_check(_x402) do
    %{
      level: :warn,
      code: "bazaar_missing",
      message:
        "No extensions.bazaar discovery metadata detected (recommended for agentic.market / x402 Bazaar discovery)."
    }
  end

  defp recipient_checks(%{recipient_status: :burn_address, recipient: addr}, label) do
    [
      %{
        level: :fail,
        code: "invalid_pay_to",
        message:
          "#{label} is the zero burn address (#{addr}); payments would be permanently lost."
      }
    ]
  end

  defp recipient_checks(%{recipient_status: :malformed, recipient: addr, network: net}, label) do
    [
      %{
        level: :fail,
        code: "invalid_pay_to",
        message: "#{label} '#{addr}' is not a valid address for network #{net}."
      }
    ]
  end

  defp recipient_checks(_pricing, _label), do: []

  defp price_sanity_checks(%{atomic_amount: amount}, rail)
       when is_integer(amount) and amount <= 0 do
    [
      %{
        level: :fail,
        code: "price_non_positive",
        message:
          "#{rail} payment amount is #{amount}; must be a positive integer in atomic units."
      }
    ]
  end

  defp price_sanity_checks(%{usd_amount: usd, amount_display: display}, rail)
       when is_number(usd) and usd > @max_sane_usd do
    [
      %{
        level: :warn,
        code: "price_unusually_high",
        message:
          "#{rail} decoded price is #{display} (> $100). Check token decimal precision (USDC uses 6 decimals, not 18)."
      }
    ]
  end

  defp price_sanity_checks(_pricing, _rail), do: []

  defp timeout_checks(seconds, label)
       when is_integer(seconds) and seconds > 0 and seconds < @min_safe_timeout_seconds do
    [
      %{
        level: :warn,
        code: "timeout_too_short",
        message:
          "#{label} is only #{seconds}s (< #{@min_safe_timeout_seconds}s); agents may time out while signing and settling."
      }
    ]
  end

  defp timeout_checks(_seconds, _label), do: []

  defp mpp_checks(%{present?: false}, _headers, _cors, _pricing), do: []

  defp mpp_checks(%{challenges: challenges}, headers, cors, mpp_pricing) do
    first = List.first(challenges) || %{}

    [
      mpp_challenge_check(first),
      mpp_cache_check(headers),
      mpp_vary_check(headers),
      mpp_expose_check(cors)
    ] ++
      recipient_checks(mpp_pricing, "MPP recipient") ++
      price_sanity_checks(mpp_pricing, "MPP") ++
      timeout_checks(mpp_pricing && mpp_pricing.ttl_seconds, "MPP expires TTL")
  end

  defp mpp_challenge_check(%{valid?: true, method: method, intent: intent}) do
    %{
      level: :pass,
      code: "mpp_valid",
      message:
        "Valid MPP WWW-Authenticate: Payment challenge (method=#{method}, intent=#{intent})."
    }
  end

  defp mpp_challenge_check(first) do
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

  defp mpp_cache_check(headers) do
    cache = headers |> Map.get("cache-control", []) |> Enum.join(",") |> String.downcase()

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
  end

  defp mpp_vary_check(headers) do
    vary = headers |> Map.get("vary", []) |> Enum.join(",") |> String.downcase()

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
  end

  defp mpp_expose_check(%{mpp_exposed?: true}) do
    %{
      level: :pass,
      code: "mpp_cors_expose",
      message: "CORS exposes WWW-Authenticate for browser/WebMCP agents."
    }
  end

  defp mpp_expose_check(_cors) do
    %{
      level: :warn,
      code: "mpp_cors_missing",
      message:
        "Access-Control-Expose-Headers does not list WWW-Authenticate (browser agents cannot read the MPP challenge)."
    }
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

  defp dual_checks(%{present?: true}, %{present?: true}, pricing) do
    base = [
      %{
        level: :pass,
        code: "dual_protocol",
        message: "Dual-rail HTTP 402 endpoint detected: advertises both x402 and MPP challenges."
      }
    ]

    base ++ dual_price_parity_checks(pricing.x402, pricing.mpp)
  end

  defp dual_checks(_x402, _mpp, _pricing), do: []

  defp dual_price_parity_checks(
         %{usd_amount: x_usd, amount_display: x_disp},
         %{usd_amount: m_usd, amount_display: m_disp}
       )
       when is_number(x_usd) and is_number(m_usd) and x_usd > 0 and m_usd > 0 do
    ratio = abs(x_usd - m_usd) / max(x_usd, m_usd)

    if ratio > @dual_price_tolerance do
      [
        %{
          level: :warn,
          code: "dual_price_mismatch",
          message: "Dual-rail price mismatch: x402 charges #{x_disp} while MPP charges #{m_disp}."
        }
      ]
    else
      []
    end
  end

  defp dual_price_parity_checks(_x402_pricing, _mpp_pricing), do: []

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
        pricing_summary_line("x402", result.pricing.x402),
        pricing_summary_line("MPP", result.pricing.mpp),
        if(result.cors.tested?,
          do:
            "- CORS `OPTIONS` preflight: `HTTP #{result.cors.preflight_status || "error"}` (`preflight_ok=#{result.cors.preflight_ok}`)"
        ),
        header_summary_line("Location", headers["location"]),
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
        "site" => host,
        "title" => headline,
        "page_url" => result.url,
        "tags" => tags,
        "body" => body_markdown
      })

    %{
      site: host,
      title: headline,
      page_url: result.url,
      tags: tags,
      body_markdown: body_markdown,
      forum_url: "/patchbay/forum?" <> query
    }
  end

  defp pricing_summary_line(_label, nil), do: nil

  defp pricing_summary_line(label, p) do
    "- #{label} Terms: `#{p.amount_display || p.raw_amount}` on `#{p.rail_label}`"
  end

  defp header_summary_line(_name, nil), do: nil
  defp header_summary_line(_name, []), do: nil

  defp header_summary_line(name, values) do
    joined = values |> Enum.join(", ") |> String.slice(0, 140)
    "- `#{name}`: `#{joined}`"
  end

  # --- Decoding helpers ---

  defp decode_b64_any(str) do
    case Base.decode64(str, ignore: :whitespace) do
      {:ok, bytes} ->
        {:ok, bytes}

      :error ->
        Base.url_decode64(str, padding: false)
    end
  end

  defp parse_json(text) when is_binary(text) and text != "" do
    case Jason.decode(text) do
      {:ok, value} -> value
      _ -> nil
    end
  end

  defp parse_json(_other), do: nil
end
