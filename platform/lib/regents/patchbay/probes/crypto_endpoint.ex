defmodule Regents.Patchbay.Probes.CryptoEndpoint do
  @moduledoc """
  SSRF-hardened live TLS and cryptographic readiness probe for Patchbay.

  Resolves the target host once through `RegentHttp.Public.resolve_public_ip/2`
  and connects directly to the validated public IP while keeping the original
  hostname for SNI and RFC 6125 certificate verification. Performs bounded
  handshakes to distinguish:

  - **Confidentiality (Key Exchange)**: whether the server actually completes a
    hybrid post-quantum TLS 1.3 handshake (`X25519MLKEM768`,
    `SecP256r1MLKEM768`, or `SecP384r1MLKEM1024`), accepts hybrid PQ
    ClientHellos cleanly while falling back to classical ECC, or suffers
    middlebox intolerance when a PQ ClientHello is offered.
  - **Authentication (Certificate Chain)**: leaf certificate public key type
    and signature algorithm, preventing misleading "quantum-safe" claims when
    only key exchange has migrated while signatures remain ECC or RSA.
  - **Reproducible verification digest**: deterministic SHA-256 fingerprint of
    the observed transport and certificate facts for before-and-after migration
    receipts and prefilled Patchbay board reports.
  """

  alias RegentHttp.Public

  @max_url_bytes 512
  @connect_timeout_ms 5_000
  @hybrid_pq_groups [:x25519mlkem768, :secp256r1mlkem768, :secp384r1mlkem1024]
  @classical_groups [:x25519, :secp256r1, :secp384r1]

  @doc """
  Probe a public `https://` URL for live TLS key-exchange agility, hybrid
  post-quantum negotiation, PQ ClientHello middlebox tolerance, and certificate
  signature posture.
  """
  @spec probe(String.t()) :: {:ok, map()} | {:error, String.t()}
  def probe(url) when is_binary(url) do
    trimmed = normalize_url(url)

    with {:ok, uri} <- validate_public_uri(trimmed),
         {:ok, ip} <- resolve_public_ip(uri.host) do
      started = System.monotonic_time(:millisecond)
      supported_groups = supported_ssl_groups()
      pq_supported = Enum.filter(@hybrid_pq_groups, &(&1 in supported_groups))

      hybrid_offer =
        ssl_handshake(
          ip,
          uri.port,
          uri.host,
          pq_supported ++ @classical_groups,
          [:"tlsv1.3", :"tlsv1.2"]
        )

      {pq_group, classical_fallback} =
        probe_pq_and_fallback(hybrid_offer, ip, uri.port, uri.host, pq_supported)

      downgrade_offer =
        probe_downgrade(hybrid_offer, classical_fallback, ip, uri.port, uri.host)

      latency_ms = max(0, System.monotonic_time(:millisecond) - started)

      {:ok,
       analyze_handshake(%{
         url: trimmed,
         host: uri.host,
         port: uri.port,
         latency_ms: latency_ms,
         runtime_pq_groups: Enum.map(pq_supported, &group_label/1),
         hybrid_offer: hybrid_offer,
         negotiated_pq_group: pq_group,
         classical_fallback: classical_fallback,
         downgrade_offer: downgrade_offer
       })}
    end
  end

  def probe(_other), do: {:error, "Provide a valid public https:// URL."}

  @doc """
  Pure analyzer over observed handshake facts. Exposed for deterministic
  verification without network I/O.
  """
  @spec analyze_handshake(map()) :: map()
  def analyze_handshake(capture) when is_map(capture) do
    now = Map.get(capture, :now) || DateTime.utc_now()
    checked_at = DateTime.to_iso8601(now)
    url = capture.url
    host = capture.host
    port = Map.get(capture, :port, 443)
    latency_ms = Map.get(capture, :latency_ms, 0)
    hybrid = capture.hybrid_offer
    pq_group = capture.negotiated_pq_group
    classical = capture.classical_fallback
    downgrade_offer = Map.get(capture, :downgrade_offer)

    {tls_info, cert_info, middlebox_intolerant?} =
      extract_tls_and_cert(hybrid, classical)

    kex_status = classify_kex(hybrid, pq_group, middlebox_intolerant?)
    auth_status = classify_auth(cert_info)
    downgrade = analyze_downgrade(downgrade_offer)
    checks = build_checks(tls_info, cert_info, kex_status, auth_status, pq_group, downgrade)
    verdict = compute_verdict(kex_status, tls_info, checks)

    canonical_facts = %{
      host: host,
      port: port,
      protocol: tls_info.protocol,
      cipher_suite: tls_info.cipher_suite,
      key_exchange_status: Atom.to_string(kex_status),
      negotiated_pq_group: pq_group,
      middlebox_pq_intolerant: middlebox_intolerant?,
      tls_1_2_downgrade_accepted: downgrade.tls_1_2_accepted?,
      auth_status: Atom.to_string(auth_status),
      leaf_key_algorithm: cert_info && cert_info.public_key_algorithm,
      leaf_signature_algorithm: cert_info && cert_info.signature_algorithm
    }

    verification_digest = "sha256:" <> sha256_hex(Jason.encode!(canonical_facts))

    result = %{
      url: url,
      host: host,
      port: port,
      latency_ms: latency_ms,
      verdict: verdict,
      confidentiality: %{
        status: Atom.to_string(kex_status),
        hybrid_pqc_negotiated?: not is_nil(pq_group),
        negotiated_pq_group: pq_group,
        pq_client_hello_tolerated?: not middlebox_intolerant?,
        tls_protocol: tls_info.protocol,
        cipher_suite: tls_info.cipher_suite
      },
      downgrade: downgrade,
      authentication: %{
        status: Atom.to_string(auth_status),
        pqc_certificate?: auth_status == :pqc_signature,
        leaf_certificate: cert_info
      },
      runtime_pq_groups: Map.get(capture, :runtime_pq_groups, []),
      checks: checks,
      playbook_slug: "ecc-pqc-migration-audit",
      verification_digest: verification_digest,
      checked_at: checked_at
    }

    Map.put(result, :report_prefill, build_report_prefill(result))
  end

  @doc """
  Compare two `probe/1` reports (before vs. after migration) and produce a
  deterministic before/after migration proof receipt.
  """
  @spec diff_reports(map(), map()) :: {:ok, map()} | {:error, String.t()}
  def diff_reports(before_report, after_report)
      when is_map(before_report) and is_map(after_report) do
    b = extract_comparable(before_report)
    a = extract_comparable(after_report)

    if is_nil(b.digest) or is_nil(a.digest) do
      {:error, "Both before and after probe reports must include verification_digest."}
    else
      {improvements, regressions, unchanged} = compare_endpoints(b, a)
      status = diff_status(improvements, regressions)
      migration_verified? = improvements != [] and regressions == []

      receipt_payload = %{
        before_digest: b.digest,
        after_digest: a.digest,
        status: status,
        improvements: Enum.map(improvements, & &1.code),
        regressions: Enum.map(regressions, & &1.code)
      }

      {:ok,
       %{
         kind: "endpoint_crypto_diff",
         host_before: b.host,
         host_after: a.host,
         host_changed?: b.host != a.host,
         verdict_before: b.verdict,
         verdict_after: a.verdict,
         before_digest: b.digest,
         after_digest: a.digest,
         status: status,
         migration_verified?: migration_verified?,
         improvements: improvements,
         regressions: regressions,
         unchanged: unchanged,
         receipt_digest: "sha256:" <> sha256_hex(Jason.encode!(receipt_payload))
       }}
    end
  end

  def diff_reports(_before, _after),
    do: {:error, "Provide both before and after probe report maps."}

  # --- Network probes ---

  defp probe_pq_and_fallback({:ok, _info}, ip, port, host, pq_supported) do
    pq_group = find_negotiated_pq_group(ip, port, host, pq_supported)
    {pq_group, nil}
  end

  defp probe_pq_and_fallback({:error, _reason}, ip, port, host, _pq_supported) do
    classical = ssl_handshake(ip, port, host, @classical_groups, [:"tlsv1.3", :"tlsv1.2"])
    {nil, classical}
  end

  defp probe_downgrade({:ok, _}, _classical, ip, port, host),
    do: ssl_handshake(ip, port, host, [], [:"tlsv1.2"])

  defp probe_downgrade(_hybrid, {:ok, _}, ip, port, host),
    do: ssl_handshake(ip, port, host, [], [:"tlsv1.2"])

  defp probe_downgrade(_hybrid, _classical, _ip, _port, _host), do: nil

  defp find_negotiated_pq_group(_ip, _port, _host, []), do: nil

  defp find_negotiated_pq_group(ip, port, host, [group | rest]) do
    case ssl_handshake(ip, port, host, [group], [:"tlsv1.3"]) do
      {:ok, _info} -> group_label(group)
      {:error, _reason} -> find_negotiated_pq_group(ip, port, host, rest)
    end
  end

  defp ssl_handshake(ip, port, host, groups, versions) do
    opts =
      [
        :binary,
        {:active, false},
        {:verify, :verify_peer},
        {:cacerts, :public_key.cacerts_get()},
        {:server_name_indication, String.to_charlist(host)},
        {:customize_hostname_check,
         [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]},
        {:versions, versions},
        {:log_level, :none}
      ] ++ if(groups == [], do: [], else: [{:supported_groups, groups}])

    case :ssl.connect(ip, port, opts, @connect_timeout_ms) do
      {:ok, sock} ->
        info = read_connection_info(sock)
        :ssl.close(sock)
        {:ok, info}

      {:error, reason} ->
        {:error, format_ssl_error(reason)}
    end
  end

  defp read_connection_info(sock) do
    {protocol, cipher} =
      case :ssl.connection_information(sock, [:protocol, :selected_cipher_suite]) do
        {:ok, props} ->
          proto = props |> Keyword.get(:protocol) |> format_protocol()
          suite = props |> Keyword.get(:selected_cipher_suite) |> format_cipher_suite()
          {proto, suite}

        _ ->
          {"unknown", "unknown"}
      end

    cert =
      case :ssl.peercert(sock) do
        {:ok, der} -> decode_certificate(der)
        _ -> nil
      end

    %{protocol: protocol, cipher_suite: cipher, certificate: cert}
  end

  defp supported_ssl_groups do
    :ssl.groups()
  rescue
    _ -> []
  end

  # --- Certificate decoding ---

  defp decode_certificate(der) when is_binary(der) do
    cert = :public_key.pkix_decode_cert(der, :otp)
    tbs = elem(cert, 1)
    sig_alg = elem(cert, 2)
    issuer = elem(tbs, 4)
    validity = elem(tbs, 5)
    subject = elem(tbs, 6)
    spki = elem(tbs, 7)

    {pk_family, pk_label} = classify_spki(spki)
    {sig_family, sig_label} = classify_sig_alg(sig_alg)

    %{
      subject: format_rdn(subject),
      issuer: format_rdn(issuer),
      not_before: format_validity_time(elem(validity, 1)),
      not_after: format_validity_time(elem(validity, 2)),
      public_key_family: pk_family,
      public_key_algorithm: pk_label,
      signature_family: sig_family,
      signature_algorithm: sig_label,
      sha256_fingerprint: sha256_hex(der)
    }
  rescue
    _ -> nil
  end

  @ec_pk_oid {1, 2, 840, 10_045, 2, 1}
  @rsa_pk_oid {1, 2, 840, 113_549, 1, 1, 1}

  @ec_curve_labels %{
    {1, 2, 840, 10_045, 3, 1, 7} => "ECDSA P-256 (secp256r1)",
    {1, 3, 132, 0, 34} => "ECDSA P-384 (secp384r1)",
    {1, 3, 132, 0, 35} => "ECDSA P-521 (secp521r1)"
  }

  @direct_pk_oids %{
    {1, 3, 101, 112} => {"ecc", "Ed25519"},
    {1, 3, 101, 113} => {"ecc", "Ed448"},
    {2, 16, 840, 1, 101, 3, 4, 3, 17} => {"pqc", "ML-DSA-44"},
    {2, 16, 840, 1, 101, 3, 4, 3, 18} => {"pqc", "ML-DSA-65"},
    {2, 16, 840, 1, 101, 3, 4, 3, 19} => {"pqc", "ML-DSA-87"}
  }

  @sig_alg_oids %{
    {1, 2, 840, 10_045, 4, 3, 2} => {"ecc", "ecdsa-with-SHA256"},
    {1, 2, 840, 10_045, 4, 3, 3} => {"ecc", "ecdsa-with-SHA384"},
    {1, 2, 840, 10_045, 4, 3, 4} => {"ecc", "ecdsa-with-SHA512"},
    {1, 3, 101, 112} => {"ecc", "Ed25519"},
    {1, 3, 101, 113} => {"ecc", "Ed448"},
    {1, 2, 840, 113_549, 1, 1, 11} => {"rsa", "sha256WithRSAEncryption"},
    {1, 2, 840, 113_549, 1, 1, 12} => {"rsa", "sha384WithRSAEncryption"},
    {1, 2, 840, 113_549, 1, 1, 13} => {"rsa", "sha512WithRSAEncryption"},
    {1, 2, 840, 113_549, 1, 1, 10} => {"rsa", "RSASSA-PSS"},
    {2, 16, 840, 1, 101, 3, 4, 3, 17} => {"pqc", "ML-DSA-44"},
    {2, 16, 840, 1, 101, 3, 4, 3, 18} => {"pqc", "ML-DSA-65"},
    {2, 16, 840, 1, 101, 3, 4, 3, 19} => {"pqc", "ML-DSA-87"}
  }

  defp classify_spki({:OTPSubjectPublicKeyInfo, {:PublicKeyAlgorithm, @ec_pk_oid, params}, _pk}) do
    label =
      case params do
        {:namedCurve, curve_oid} -> Map.get(@ec_curve_labels, curve_oid, "ECDSA (other curve)")
        _ -> "ECDSA (other curve)"
      end

    {"ecc", label}
  end

  defp classify_spki({:OTPSubjectPublicKeyInfo, {:PublicKeyAlgorithm, @rsa_pk_oid, _}, pub_key}) do
    bits = rsa_key_bits(pub_key)
    {"rsa", if(bits, do: "RSA-#{bits}", else: "RSA")}
  end

  defp classify_spki({:OTPSubjectPublicKeyInfo, {:PublicKeyAlgorithm, oid, _params}, _pub_key}) do
    Map.get(@direct_pk_oids, oid) || slh_dsa_or_unknown(oid)
  end

  defp classify_spki(_), do: {"unknown", "unknown"}

  defp classify_sig_alg({:SignatureAlgorithm, oid, _params}) do
    Map.get(@sig_alg_oids, oid) || slh_dsa_or_unknown(oid)
  end

  defp classify_sig_alg(_), do: {"unknown", "unknown"}

  defp slh_dsa_or_unknown({2, 16, 840, 1, 101, 3, 4, 3, n}) when n in 20..31,
    do: {"pqc", "SLH-DSA"}

  defp slh_dsa_or_unknown(oid), do: {"unknown", format_oid(oid)}

  defp rsa_key_bits({:RSAPublicKey, modulus, _exp}) when is_integer(modulus) and modulus > 0 do
    modulus |> :binary.encode_unsigned() |> bit_size()
  end

  defp rsa_key_bits(_), do: nil

  defp format_rdn({:rdnSequence, sets}) when is_list(sets) do
    sets
    |> List.flatten()
    |> Enum.flat_map(&extract_cn_or_o/1)
    |> Enum.join(", ")
  end

  defp format_rdn(_), do: ""

  defp extract_cn_or_o({:AttributeTypeAndValue, {2, 5, 4, 3}, val}),
    do: ["CN=" <> decode_asn1_string(val)]

  defp extract_cn_or_o({:AttributeTypeAndValue, {2, 5, 4, 10}, val}),
    do: ["O=" <> decode_asn1_string(val)]

  defp extract_cn_or_o(_), do: []

  defp decode_asn1_string({_tag, value}), do: to_string(value)
  defp decode_asn1_string(value) when is_list(value), do: List.to_string(value)
  defp decode_asn1_string(value) when is_binary(value), do: value
  defp decode_asn1_string(_), do: ""

  defp format_validity_time({:utcTime, chars}) do
    str = List.to_string(chars)

    case Regex.run(~r/\A(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z\z/, str) do
      [_, yy, mo, dd, hh, mm, ss] ->
        year = if String.to_integer(yy) >= 50, do: "19" <> yy, else: "20" <> yy
        "#{year}-#{mo}-#{dd}T#{hh}:#{mm}:#{ss}Z"

      _ ->
        str
    end
  end

  defp format_validity_time({:generalTime, chars}) do
    str = List.to_string(chars)

    case Regex.run(~r/\A(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z\z/, str) do
      [_, yyyy, mo, dd, hh, mm, ss] -> "#{yyyy}-#{mo}-#{dd}T#{hh}:#{mm}:#{ss}Z"
      _ -> str
    end
  end

  defp format_validity_time(_), do: nil

  # --- Analysis ---

  defp extract_tls_and_cert({:ok, info}, _classical) do
    {%{protocol: info.protocol, cipher_suite: info.cipher_suite, error: nil}, info.certificate,
     false}
  end

  defp extract_tls_and_cert({:error, _hybrid_err}, {:ok, info}) do
    {%{protocol: info.protocol, cipher_suite: info.cipher_suite, error: nil}, info.certificate,
     true}
  end

  defp extract_tls_and_cert({:error, err}, _classical) do
    {%{protocol: nil, cipher_suite: nil, error: err}, nil, false}
  end

  defp classify_kex(_hybrid, pq_group, _intolerant?) when is_binary(pq_group), do: :hybrid_pqc
  defp classify_kex(_hybrid, nil, true), do: :pq_intolerant
  defp classify_kex({:ok, _}, nil, false), do: :classical_ecc_only
  defp classify_kex(_hybrid, nil, false), do: :unreachable

  defp classify_auth(nil), do: :unknown
  defp classify_auth(%{public_key_family: "pqc", signature_family: "pqc"}), do: :pqc_signature
  defp classify_auth(%{public_key_family: "ecc"}), do: :classical_ecc
  defp classify_auth(%{public_key_family: "rsa"}), do: :classical_rsa
  defp classify_auth(_), do: :unknown

  defp analyze_downgrade(nil) do
    %{
      tested?: false,
      tls_1_2_accepted?: false,
      negotiated_protocol: nil,
      negotiated_cipher_suite: nil,
      status: "not_tested"
    }
  end

  defp analyze_downgrade({:ok, info}) do
    %{
      tested?: true,
      tls_1_2_accepted?: true,
      negotiated_protocol: info.protocol,
      negotiated_cipher_suite: info.cipher_suite,
      status: "tls_1_2_downgrade_accepted"
    }
  end

  defp analyze_downgrade({:error, _reason}) do
    %{
      tested?: true,
      tls_1_2_accepted?: false,
      negotiated_protocol: nil,
      negotiated_cipher_suite: nil,
      status: "tls_1_3_enforced"
    }
  end

  defp build_checks(tls_info, cert_info, kex_status, auth_status, pq_group, downgrade) do
    [
      tls_protocol_check(tls_info),
      kex_check(kex_status, pq_group),
      middlebox_check(kex_status),
      downgrade_check(downgrade),
      auth_check(auth_status, cert_info)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp downgrade_check(%{tested?: false}), do: nil

  defp downgrade_check(%{tls_1_2_accepted?: true, negotiated_cipher_suite: suite}) do
    %{
      level: :warn,
      code: "tls_1_2_downgrade_accepted",
      message:
        "Downgrade check: endpoint accepted a forced TLS 1.2 classical handshake (#{suite}). Clients without strict TLS 1.3 minimum policy can be downgraded off hybrid PQ key exchange."
    }
  end

  defp downgrade_check(%{tls_1_2_accepted?: false}) do
    %{
      level: :pass,
      code: "tls_1_3_enforced",
      message:
        "Downgrade check: endpoint refused a forced TLS 1.2 classical handshake, blocking protocol downgrade off TLS 1.3."
    }
  end

  defp tls_protocol_check(%{error: err}) when is_binary(err) do
    %{level: :fail, code: "tls_connect_failed", message: "TLS handshake failed: #{err}."}
  end

  defp tls_protocol_check(%{protocol: "TLS 1.3", cipher_suite: suite}) do
    %{
      level: :pass,
      code: "tls_1_3_active",
      message: "Negotiated TLS 1.3 (#{suite})."
    }
  end

  defp tls_protocol_check(%{protocol: proto}) do
    %{
      level: :fail,
      code: "tls_legacy_version",
      message:
        "Negotiated #{proto || "unknown"} instead of TLS 1.3; hybrid PQ key exchange requires TLS 1.3."
    }
  end

  defp kex_check(:hybrid_pqc, pq_group) do
    %{
      level: :pass,
      code: "pq_kex_negotiated",
      message:
        "Confidentiality: endpoint completed strict hybrid post-quantum key exchange (#{pq_group})."
    }
  end

  defp kex_check(:classical_ecc_only, _pq_group) do
    %{
      level: :warn,
      code: "pq_kex_missing",
      message:
        "Confidentiality: endpoint negotiated classical ECC key exchange only (no X25519MLKEM768 or P-curve ML-KEM hybrid). Recorded traffic remains exposed to harvest-now-decrypt-later ECC compromise."
    }
  end

  defp kex_check(:pq_intolerant, _pq_group) do
    %{
      level: :fail,
      code: "pq_client_hello_intolerant",
      message:
        "Middlebox failure: endpoint rejected a hybrid PQ ClientHello but succeeded with a classical-only ClientHello. A proxy, firewall, or older TLS terminator is choking on larger PQ key shares."
    }
  end

  defp kex_check(:unreachable, _pq_group), do: nil

  defp middlebox_check(:pq_intolerant), do: nil
  defp middlebox_check(:unreachable), do: nil

  defp middlebox_check(_ok) do
    %{
      level: :pass,
      code: "pq_client_hello_tolerated",
      message: "Endpoint tolerated a hybrid PQ ClientHello without connection reset or downgrade."
    }
  end

  defp auth_check(:pqc_signature, cert) do
    %{
      level: :pass,
      code: "cert_auth_pqc",
      message:
        "Authentication: leaf certificate uses post-quantum key (#{cert.public_key_algorithm}) and signature (#{cert.signature_algorithm})."
    }
  end

  defp auth_check(:classical_ecc, cert) do
    %{
      level: :warn,
      code: "cert_auth_classical_ecc",
      message:
        "Authentication: leaf certificate still relies on classical ECC (#{cert.public_key_algorithm}, signed with #{cert.signature_algorithm}). Transport key exchange does not protect against forged ECC certificates."
    }
  end

  defp auth_check(:classical_rsa, cert) do
    %{
      level: :warn,
      code: "cert_auth_classical_rsa",
      message:
        "Authentication: leaf certificate relies on classical RSA (#{cert.public_key_algorithm}, signed with #{cert.signature_algorithm})."
    }
  end

  defp auth_check(_other, _cert), do: nil

  defp compute_verdict(:hybrid_pqc, %{protocol: "TLS 1.3"}, checks) do
    if Enum.any?(checks, &(&1.level == :fail)), do: :fail, else: :pass
  end

  defp compute_verdict(:classical_ecc_only, %{protocol: "TLS 1.3"}, checks) do
    if Enum.any?(checks, &(&1.level == :fail)), do: :fail, else: :warn
  end

  defp compute_verdict(_, _, _), do: :fail

  defp build_report_prefill(result) do
    summary =
      Enum.map_join(result.checks, "\n", fn chk ->
        "- [#{String.upcase(to_string(chk.level))}] `#{chk.code}`: #{chk.message}"
      end)

    title =
      case result.verdict do
        :pass ->
          "Crypto probe verified hybrid PQ TLS on #{result.host}"

        :warn ->
          "#{result.host}: TLS negotiated classical ECC only (no hybrid PQ key exchange)"

        :fail ->
          "#{result.host}: TLS crypto probe failed (#{result.confidentiality.status})"
      end

    body = """
    ### Patchbay Live Crypto & PQC Probe
    - **Target:** `#{result.url}`
    - **Verdict:** `#{result.verdict}`
    - **Confidentiality (Key Exchange):** `#{result.confidentiality.status}` (PQ group: `#{result.confidentiality.negotiated_pq_group || "none"}`, TLS: `#{result.confidentiality.tls_protocol || "unknown"}`)
    - **Downgrade Simulation (TLS 1.2):** `#{result.downgrade.status}`
    - **Authentication (Leaf Cert):** `#{result.authentication.status}`
    - **Verification Digest:** `#{result.verification_digest}`
    - **Checked at:** `#{result.checked_at}`

    ### Checks
    #{summary}
    """

    query =
      URI.encode_query(%{
        "origin" => result.host,
        "title" => title,
        "body" => String.trim(body),
        "tag" => "pqc"
      })

    %{
      origin: result.host,
      title: title,
      body: String.trim(body),
      forum_url: "/patchbay/forum?#{query}"
    }
  end

  # --- Helpers ---

  defp normalize_url(url) do
    trimmed = String.trim(url)

    if trimmed != "" and not String.contains?(trimmed, "://") do
      "https://" <> trimmed
    else
      trimmed
    end
  end

  defp validate_public_uri(url) do
    cond do
      byte_size(url) > @max_url_bytes ->
        {:error, "URL exceeds 512 character limit."}

      match?({:ok, _}, Public.uri(url)) ->
        Public.uri(url)

      true ->
        {:error, "Provide a valid public https:// URL (localhost and private IPs are blocked)."}
    end
  end

  defp resolve_public_ip(host) do
    case Public.resolve_public_ip(host, @connect_timeout_ms) do
      {:ok, ip} -> {:ok, ip}
      {:error, :non_public_address} -> {:error, "Refused: host resolved to a non-public address."}
      {:error, :dns_error} -> {:error, "DNS lookup failed for #{host}."}
      {:error, :timeout} -> {:error, "DNS lookup timed out for #{host}."}
    end
  end

  defp group_label(:x25519mlkem768), do: "X25519MLKEM768"
  defp group_label(:secp256r1mlkem768), do: "SecP256r1MLKEM768"
  defp group_label(:secp384r1mlkem1024), do: "SecP384r1MLKEM1024"
  defp group_label(other), do: Atom.to_string(other)

  defp format_protocol(:"tlsv1.3"), do: "TLS 1.3"
  defp format_protocol(:"tlsv1.2"), do: "TLS 1.2"
  defp format_protocol(other) when is_atom(other), do: Atom.to_string(other)
  defp format_protocol(_), do: "unknown"

  defp format_cipher_suite(%{cipher: cipher, prf: prf}) do
    "#{String.upcase(to_string(cipher))}_#{String.upcase(to_string(prf))}"
  end

  defp format_cipher_suite(_), do: "unknown"

  defp format_oid(oid) when is_tuple(oid) do
    oid |> Tuple.to_list() |> Enum.map_join(".", &Integer.to_string/1)
  end

  defp format_ssl_error({:tls_alert, {alert, _detail}}), do: "TLS alert (#{alert})"
  defp format_ssl_error(:timeout), do: "connection timed out"
  defp format_ssl_error(:econnrefused), do: "connection refused"
  defp format_ssl_error(:closed), do: "connection closed by peer during handshake"
  defp format_ssl_error(reason), do: inspect(reason)

  # --- Before/After Diff Helpers ---

  defp extract_comparable(report) do
    conf = field(report, :confidentiality) || %{}
    down = field(report, :downgrade) || %{}
    auth = field(report, :authentication) || %{}

    %{
      host: field(report, :host),
      verdict: to_str(field(report, :verdict)),
      digest: field(report, :verification_digest),
      tls_protocol: field(conf, :tls_protocol),
      hybrid_pqc?: truthy?(field(conf, :hybrid_pqc_negotiated?)),
      pq_group: field(conf, :negotiated_pq_group),
      tolerated?: truthy?(field(conf, :pq_client_hello_tolerated?)),
      kex_status: to_str(field(conf, :status)),
      downgrade_tested?: truthy?(field(down, :tested?)),
      tls_1_2_accepted?: truthy?(field(down, :tls_1_2_accepted?)),
      pqc_cert?: truthy?(field(auth, :pqc_certificate?)),
      auth_status: to_str(field(auth, :status))
    }
  end

  defp compare_endpoints(b, a) do
    deltas =
      [
        compare_hybrid_pqc(b, a),
        compare_middlebox(b, a),
        compare_downgrade(b, a),
        compare_tls_version(b, a),
        compare_cert_auth(b, a)
      ]
      |> Enum.reject(&is_nil/1)

    improvements = for {:improved, item} <- deltas, do: item
    regressions = for {:regressed, item} <- deltas, do: item
    unchanged = for {:unchanged, item} <- deltas, do: item
    {improvements, regressions, unchanged}
  end

  defp compare_hybrid_pqc(%{hybrid_pqc?: false}, %{hybrid_pqc?: true, pq_group: grp}),
    do:
      {:improved,
       %{code: "hybrid_pqc_enabled", message: "Enabled hybrid PQ key exchange (#{grp})."}}

  defp compare_hybrid_pqc(%{hybrid_pqc?: true, pq_group: grp}, %{hybrid_pqc?: false}),
    do:
      {:regressed,
       %{code: "hybrid_pqc_lost", message: "Lost hybrid PQ key exchange (was #{grp})."}}

  defp compare_hybrid_pqc(%{hybrid_pqc?: true, pq_group: grp}, %{hybrid_pqc?: true}),
    do:
      {:unchanged,
       %{code: "hybrid_pqc_preserved", message: "Hybrid PQ key exchange intact (#{grp})."}}

  defp compare_hybrid_pqc(_, _),
    do:
      {:unchanged,
       %{code: "still_classical_kex", message: "Key exchange remains classical ECC only."}}

  defp compare_middlebox(%{kex_status: "pq_intolerant"}, %{tolerated?: true}),
    do:
      {:improved,
       %{
         code: "middlebox_intolerance_fixed",
         message: "Resolved PQ ClientHello middlebox drop."
       }}

  defp compare_middlebox(%{tolerated?: true}, %{kex_status: "pq_intolerant"}),
    do:
      {:regressed,
       %{
         code: "middlebox_intolerance_introduced",
         message: "Introduced PQ ClientHello middlebox intolerance."
       }}

  defp compare_middlebox(_, _), do: nil

  defp compare_downgrade(
         %{downgrade_tested?: true, tls_1_2_accepted?: true},
         %{downgrade_tested?: true, tls_1_2_accepted?: false}
       ),
       do:
         {:improved,
          %{
            code: "tls_1_2_downgrade_closed",
            message: "Closed TLS 1.2 classical downgrade path; TLS 1.3 is now enforced."
          }}

  defp compare_downgrade(
         %{downgrade_tested?: true, tls_1_2_accepted?: false},
         %{downgrade_tested?: true, tls_1_2_accepted?: true}
       ),
       do:
         {:regressed,
          %{
            code: "tls_1_2_downgrade_opened",
            message: "Reopened TLS 1.2 classical downgrade path."
          }}

  defp compare_downgrade(%{downgrade_tested?: true, tls_1_2_accepted?: false}, %{
         downgrade_tested?: true,
         tls_1_2_accepted?: false
       }),
       do: {:unchanged, %{code: "tls_1_3_enforced", message: "TLS 1.3 minimum enforcement held."}}

  defp compare_downgrade(_, _), do: nil

  defp compare_tls_version(%{tls_protocol: b}, %{tls_protocol: "TLS 1.3"}) when b != "TLS 1.3",
    do:
      {:improved,
       %{code: "tls_1_3_upgraded", message: "Upgraded negotiated transport to TLS 1.3."}}

  defp compare_tls_version(%{tls_protocol: "TLS 1.3"}, %{tls_protocol: a}) when a != "TLS 1.3",
    do:
      {:regressed,
       %{code: "tls_1_3_downgraded", message: "Dropped from TLS 1.3 to #{a || "unreachable"}."}}

  defp compare_tls_version(_, _), do: nil

  defp compare_cert_auth(%{pqc_cert?: false}, %{pqc_cert?: true}),
    do:
      {:improved,
       %{code: "pqc_certificate_enabled", message: "Leaf certificate migrated to PQC signature."}}

  defp compare_cert_auth(%{pqc_cert?: true}, %{pqc_cert?: false}),
    do:
      {:regressed,
       %{code: "pqc_certificate_reverted", message: "Leaf certificate reverted to classical key."}}

  defp compare_cert_auth(_, %{auth_status: auth}) when is_binary(auth) and auth != "",
    do:
      {:unchanged,
       %{code: "cert_auth_unchanged", message: "Leaf certificate posture unchanged (#{auth})."}}

  defp compare_cert_auth(_, _), do: nil

  defp diff_status([], []), do: "unchanged"
  defp diff_status([_ | _], []), do: "improved"
  defp diff_status([], [_ | _]), do: "regressed"
  defp diff_status([_ | _], [_ | _]), do: "mixed"

  defp field(map, atom_key) when is_map(map) do
    case Map.fetch(map, atom_key) do
      {:ok, value} -> value
      :error -> Map.get(map, Atom.to_string(atom_key))
    end
  end

  defp truthy?(true), do: true
  defp truthy?(_), do: false

  defp to_str(nil), do: nil
  defp to_str(val) when is_atom(val), do: Atom.to_string(val)
  defp to_str(val) when is_binary(val), do: val
  defp to_str(val), do: to_string(val)

  defp sha256_hex(bytes) when is_binary(bytes) do
    :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
  end
end
