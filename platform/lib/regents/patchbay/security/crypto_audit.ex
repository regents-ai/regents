defmodule Regents.Patchbay.Security.CryptoAudit do
  @moduledoc """
  Cryptographic dependency inventory and CycloneDX 1.6 CBOM generator for Patchbay.

  Reuses `Regents.Patchbay.Security.StackCheck.parse_manifest/1` across `package.json`,
  `package-lock.json`, `mix.lock`, `Cargo.toml`, `Cargo.lock`, `requirements.txt`,
  `uv.lock`, `go.mod`, `composer.lock`, and `name@version` lists to answer:

  1. Where does this stack rely on ECC or RSA?
  2. What does each dependency protect (confidentiality, authentication, or
     external chain authority that the app cannot migrate alone)?
  3. Which dependencies are already PQC-capable at their pinned version vs.
     requiring an upgrade or provider switch?
  4. Emits a standards-compliant CycloneDX 1.6 Cryptography Bill of Materials
     (`cbom`) and a deterministic `verification_digest` for before-and-after
     migration verification.
  """

  alias Regents.Patchbay.Security.StackCheck

  @max_input_bytes 64 * 1024

  # Curated cryptographic dependency catalog. Each rule captures what a package
  # protects, which primitives it exposes, and when a pinned version crosses a
  # real post-quantum capability boundary.
  @rules [
    # --- Rust / Cargo ---
    %{
      match: ["ring"],
      ecosystems: ["cargo", nil],
      role: "tls_and_signing",
      algorithms: ["X25519", "Ed25519", "ECDSA-P256", "ECDSA-P384", "RSA"],
      quantum_status: :ecc_only,
      exposure: :both,
      boundary: :app_owned,
      remediation:
        "Switch rustls crypto provider from `ring` to `aws-lc-rs` to enable X25519MLKEM768 hybrid TLS 1.3 and ML-DSA/ML-KEM support."
    },
    %{
      match: ["rustls"],
      ecosystems: ["cargo", nil],
      role: "tls_transport",
      algorithms: ["TLS-1.3", "X25519MLKEM768", "X25519"],
      quantum_status: :provider_dependent,
      exposure: :confidentiality,
      boundary: :app_owned,
      min_pqc_version: "0.23.0",
      remediation:
        "Ensure `rustls >= 0.23` uses the `aws-lc-rs` crypto provider (not `ring`) so TLS 1.3 negotiates X25519MLKEM768."
    },
    %{
      match: ["aws-lc-rs", "aws-lc-sys"],
      ecosystems: ["cargo", nil],
      role: "pqc_crypto_provider",
      algorithms: ["X25519MLKEM768", "ML-KEM-768", "ML-DSA-65"],
      quantum_status: :pqc_ready,
      exposure: :both,
      boundary: :app_owned,
      remediation:
        "Verify `aws-lc-rs` is wired as the active TLS/signing provider and confirm negotiated group with `patchbay_probe_crypto`."
    },
    %{
      match: ["curve25519-dalek", "ed25519-dalek", "x25519-dalek"],
      ecosystems: ["cargo", nil],
      role: "key_exchange_and_signing",
      algorithms: ["X25519", "Ed25519"],
      quantum_status: :ecc_only,
      exposure: :both,
      boundary: :app_owned,
      remediation:
        "Pair X25519 with ML-KEM-768 (X-Wing / hybrid KEM) for confidentiality and co-sign Ed25519 messages with ML-DSA-65."
    },
    %{
      match: ["k256", "p256", "p384", "secp256k1"],
      ecosystems: ["cargo", nil],
      role: "ecc_signing",
      algorithms: ["secp256k1", "ECDSA-P256"],
      quantum_status: :ecc_only,
      exposure: :authentication,
      boundary: :app_owned,
      remediation:
        "Add algorithm agility and ML-DSA-65 co-signing for application authentication; separate app auth keys from on-chain wallet keys."
    },
    %{
      match: ["dcap-qvl"],
      ecosystems: ["cargo", nil],
      role: "tee_attestation",
      algorithms: ["ECDSA-P256"],
      quantum_status: :ecc_only,
      exposure: :authentication,
      boundary: :external_hardware,
      remediation:
        "Intel TDX DCAP quotes rely on hardware-rooted ECDSA P-256; pair with hybrid PQ TLS transport and track Intel PQC attestation updates."
    },
    %{
      match: ["alloy", "alloy-signer-local", "ethers-signers"],
      ecosystems: ["cargo", nil],
      role: "onchain_wallet",
      algorithms: ["secp256k1"],
      quantum_status: :ecc_only,
      exposure: :onchain_authority,
      boundary: :external_chain,
      remediation:
        "EVM transaction signing is bound to secp256k1 on L1/L2. Keep working balances small, inventory Safe/contract authorities, and avoid exposing unused signing keys."
    },
    %{
      match: ["ml-kem", "ml-dsa", "slh-dsa", "fips203", "fips204", "fips205"],
      ecosystems: ["cargo", nil],
      role: "pqc_library",
      algorithms: ["ML-KEM", "ML-DSA", "SLH-DSA"],
      quantum_status: :pqc_ready,
      exposure: :both,
      boundary: :app_owned,
      remediation:
        "Standardized NIST PQC crate detected; verify constant-time build and policy enforcement."
    },

    # --- Elixir / Hex ---
    %{
      match: ["ex_secp256k1"],
      ecosystems: ["hex", nil],
      role: "wallet_ecdsa",
      algorithms: ["secp256k1"],
      quantum_status: :ecc_only,
      exposure: :authentication,
      boundary: :app_owned,
      remediation:
        "Keep for EVM verification only; adopt native Erlang/OTP 28.1+ `:crypto` ML-DSA-65 (`:mldsa65`) co-signing for off-chain agent auth (SIWA v3)."
    },
    %{
      match: ["jose", "joken"],
      ecosystems: ["hex", nil],
      role: "jwt_jws",
      algorithms: ["Ed25519", "ES256", "RS256"],
      quantum_status: :ecc_only,
      exposure: :authentication,
      boundary: :app_owned,
      remediation:
        "JOSE/Joken tokens default to classical EdDSA/ES256/RS256. Pair with OTP native `:mldsa65` / `:slh_dsa_*` verification for long-lived identity cards."
    },
    %{
      match: ["curvy", "ed25519"],
      ecosystems: ["hex", nil],
      role: "ecc_signing",
      algorithms: ["secp256k1", "Ed25519"],
      quantum_status: :ecc_only,
      exposure: :authentication,
      boundary: :app_owned,
      remediation:
        "Replace direct ECC-only signing with Erlang/OTP 28.1+ OpenSSL 3.5+ native `:crypto.sign(:mldsa65, ...)` or hybrid signatures."
    },
    %{
      match: ["siwa"],
      ecosystems: ["hex", nil],
      role: "agent_identity",
      algorithms: ["secp256k1", "ERC-1271", "Ed25519"],
      quantum_status: :ecc_only,
      exposure: :authentication,
      boundary: :app_owned,
      remediation:
        "Pre-enroll ML-DSA-65 backup/co-signing keys per paired agent before any ECC break (SIWA v3 hybrid policy) and run `siwa-server` on Debian Trixie (OpenSSL 3.5+)."
    },
    %{
      match: ["ethers", "regent_chain"],
      ecosystems: ["hex", nil],
      role: "onchain_wallet",
      algorithms: ["secp256k1"],
      quantum_status: :ecc_only,
      exposure: :onchain_authority,
      boundary: :external_chain,
      remediation:
        "Audit all Safe owners, upgrade admins, and session keys; separate off-chain identity from on-chain secp256k1 settlement keys."
    },

    # --- Python / PyPI ---
    %{
      match: ["cryptography"],
      ecosystems: ["pypi", nil],
      role: "crypto_runtime",
      algorithms: ["ML-DSA", "ML-KEM", "X25519", "Ed25519", "ECDSA", "RSA"],
      quantum_status: :version_gated,
      min_pqc_version: "50.0.0",
      exposure: :both,
      boundary: :app_owned,
      remediation:
        "Upgrade Python `cryptography` to `>= 50.0.2` (OpenSSL 3.5+/4.x) to access native `cryptography.hazmat.primitives.asymmetric.mldsa` and `mlkem` without `liboqs`."
    },
    %{
      match: ["eth-account", "eth-keys", "coincurve", "web3"],
      ecosystems: ["pypi", nil],
      role: "onchain_wallet",
      algorithms: ["secp256k1"],
      quantum_status: :ecc_only,
      exposure: :onchain_authority,
      boundary: :external_chain,
      remediation:
        "Keep secp256k1 scoped strictly to EVM transactions; use `cryptography >= 50` ML-DSA-65 for off-chain API/SIWA request signing."
    },
    %{
      match: ["ckzg"],
      ecosystems: ["pypi", nil],
      role: "pairing_commitments",
      algorithms: ["BLS12-381-KZG"],
      quantum_status: :ecc_only,
      exposure: :onchain_authority,
      boundary: :external_chain,
      remediation:
        "BLS12-381 KZG commitments are Ethereum L1/blob consensus dependencies; track Ethereum Lean/hash-based commitment roadmap."
    },
    %{
      match: ["ecdsa", "pynacl", "pyjwt", "python-jose"],
      ecosystems: ["pypi", nil],
      role: "ecc_signing",
      algorithms: ["ECDSA", "Ed25519", "X25519"],
      quantum_status: :ecc_only,
      exposure: :authentication,
      boundary: :app_owned,
      remediation:
        "Migrate token/message authentication away from ECC-only libraries toward algorithm-agile `ML-DSA-65` via `cryptography >= 50`."
    },

    # --- JS / TS / npm ---
    %{
      match: ["viem", "ethers", "wagmi", "@privy-io/react-auth", "@solana/web3.js"],
      ecosystems: ["npm", nil],
      role: "onchain_wallet",
      algorithms: ["secp256k1", "Ed25519"],
      quantum_status: :ecc_only,
      exposure: :onchain_authority,
      boundary: :external_chain,
      remediation:
        "Wallet/chain signing depends on L1 signature schemes. Decouple app sessions/recovery from raw wallet signatures and enforce Safe/multisig authority inventories."
    },
    %{
      match: [
        "@noble/curves",
        "@noble/secp256k1",
        "@noble/ed25519",
        "elliptic",
        "secp256k1",
        "tweetnacl"
      ],
      ecosystems: ["npm", nil],
      role: "ecc_signing",
      algorithms: ["secp256k1", "Ed25519", "X25519", "P-256"],
      quantum_status: :ecc_only,
      exposure: :both,
      boundary: :app_owned,
      remediation:
        "Introduce hybrid PQ KEM/signing (e.g., server-side native OpenSSL 3.5+ / CryptoKit or `@noble/post-quantum` for interop testing) and remove legacy `elliptic`."
    },
    %{
      match: ["jsonwebtoken", "jose"],
      ecosystems: ["npm", nil],
      role: "jwt_jws",
      algorithms: ["ES256", "EdDSA", "RS256"],
      quantum_status: :ecc_only,
      exposure: :authentication,
      boundary: :app_owned,
      remediation:
        "Keep token lifetimes short, pin explicit algorithms, and plan composite/ML-DSA-65 signing for cross-service credentials."
    },
    %{
      match: ["@noble/post-quantum"],
      ecosystems: ["npm", nil],
      role: "pqc_library",
      algorithms: ["ML-KEM", "ML-DSA", "SLH-DSA"],
      quantum_status: :pqc_ready,
      exposure: :both,
      boundary: :app_owned,
      remediation:
        "JS/TS PQC library detected. Note its README caveats on constant-time JS execution; prefer native OTP/OpenSSL/CryptoKit for high-value signing keys."
    },

    # --- Go ---
    %{
      match: [
        "golang.org/x/crypto",
        "github.com/ethereum/go-ethereum",
        "github.com/decred/dcrd/dcrec/secp256k1"
      ],
      ecosystems: ["go", nil],
      role: "ecc_signing",
      algorithms: ["X25519", "Ed25519", "secp256k1"],
      quantum_status: :ecc_only,
      exposure: :both,
      boundary: :app_owned,
      remediation:
        "Use Go 1.24+ standard `crypto/mlkem` and hybrid TLS (`X25519MLKEM768`) for transport, and pair signing paths with ML-DSA."
    },
    %{
      match: ["github.com/cloudflare/circl"],
      ecosystems: ["go", nil],
      role: "pqc_library",
      algorithms: ["ML-KEM", "ML-DSA", "SLH-DSA", "X-Wing"],
      quantum_status: :pqc_ready,
      exposure: :both,
      boundary: :app_owned,
      remediation:
        "Cloudflare CIRCL PQC library detected; verify FIPS 203/204 final parameter sets are enabled."
    },

    # --- PHP / Packagist ---
    %{
      match: [
        "lcobucci/jwt",
        "firebase/php-jwt",
        "paragonie/sodium_compat",
        "simplito/elliptic-php"
      ],
      ecosystems: ["packagist", nil],
      role: "ecc_signing",
      algorithms: ["Ed25519", "ES256", "secp256k1", "RS256"],
      quantum_status: :ecc_only,
      exposure: :authentication,
      boundary: :app_owned,
      remediation:
        "Upgrade underlying OpenSSL to 3.5+ for TLS hybrid KEM and isolate JWT/signing verification behind an algorithm-agile verifier."
    },

    # --- Runtimes (explicitly supplied in manifests or package lists) ---
    %{
      match: ["openssl"],
      ecosystems: [nil, "system", "hex", "pypi"],
      role: "crypto_runtime",
      algorithms: ["ML-KEM", "ML-DSA", "SLH-DSA", "TLS-1.3"],
      quantum_status: :version_gated,
      min_pqc_version: "3.5.0",
      exposure: :both,
      boundary: :app_owned,
      remediation:
        "Upgrade OpenSSL to `>= 3.5.0` (e.g. Debian Trixie instead of Bookworm) for native FIPS 203/204/205 support and X25519MLKEM768 TLS."
    },
    %{
      match: ["erlang", "otp"],
      ecosystems: [nil, "system", "hex"],
      role: "crypto_runtime",
      algorithms: ["ML-KEM", "ML-DSA", "SLH-DSA"],
      quantum_status: :version_gated,
      min_pqc_version: "28.1.0",
      exposure: :both,
      boundary: :app_owned,
      remediation:
        "Upgrade Erlang/OTP to `>= 28.1` linked against OpenSSL 3.5+ to use native `:crypto` ML-DSA, SLH-DSA, and ML-KEM."
    },
    %{
      match: ["go"],
      ecosystems: [nil, "system", "go"],
      role: "crypto_runtime",
      algorithms: ["X25519MLKEM768", "ML-KEM-768"],
      quantum_status: :version_gated,
      min_pqc_version: "1.24.0",
      exposure: :confidentiality,
      boundary: :app_owned,
      remediation:
        "Upgrade Go to `>= 1.24` for stdlib `crypto/mlkem` and default hybrid `X25519MLKEM768` TLS 1.3."
    }
  ]

  @doc """
  Parse raw manifest text or a structured package list and return cryptographic
  exposure findings plus a CycloneDX 1.6 CBOM.
  """
  @spec check(String.t() | [map()], keyword()) :: {:ok, map()} | {:error, String.t()}
  def check(input, opts \\ [])

  def check(input, opts) when is_binary(input) do
    if byte_size(input) > @max_input_bytes do
      {:error, "Manifest text exceeds 64 KB limit."}
    else
      packages = StackCheck.parse_manifest(input)

      if packages == [] do
        {:error,
         "No package names detected. Paste package.json, package-lock.json, mix.lock, Cargo.toml, Cargo.lock, requirements.txt, uv.lock, go.mod, composer.lock, or name@version entries."}
      else
        {:ok, evaluate(packages, opts)}
      end
    end
  end

  def check(packages, opts) when is_list(packages) do
    normalized =
      packages
      |> Enum.flat_map(&normalize_entry/1)
      |> Enum.uniq_by(&{&1.ecosystem, &1.name, &1.version})

    if normalized == [] do
      {:error, "Provide at least one package name to audit."}
    else
      {:ok, evaluate(normalized, opts)}
    end
  end

  def check(_other, _opts), do: {:error, "Provide manifest text or a list of packages."}

  @doc """
  Pure evaluator over parsed `{ecosystem, name, version}` entries.
  """
  @spec evaluate([StackCheck.parsed_package()], keyword()) :: map()
  def evaluate(packages, opts \\ []) when is_list(packages) do
    include_cbom? = Keyword.get(opts, :include_cbom, true)
    now = Keyword.get(opts, :now) || DateTime.utc_now()
    package_names = MapSet.new(packages, & &1.name)

    evaluated =
      packages
      |> Enum.flat_map(&evaluate_package(&1, package_names))
      |> Enum.uniq_by(&{&1.ecosystem, &1.package, &1.installed_version})

    {ready, findings} = Enum.split_with(evaluated, &(&1.status == "pqc_ready"))

    sorted_findings =
      Enum.sort_by(findings, fn item ->
        {severity_rank(item.severity), item.boundary != "app_owned", item.package}
      end)

    canonical_facts =
      Enum.map(evaluated, fn item ->
        %{
          ecosystem: item.ecosystem,
          package: item.package,
          version: item.installed_version,
          status: item.status,
          algorithms: item.algorithms
        }
      end)

    digest =
      "sha256:" <>
        (:crypto.hash(:sha256, Jason.encode!(canonical_facts)) |> Base.encode16(case: :lower))

    base = %{
      package_count: length(packages),
      versioned_package_count: Enum.count(packages, &(not is_nil(&1.version))),
      crypto_dependency_count: length(evaluated),
      ecc_exposed_count:
        Enum.count(sorted_findings, &(&1.status in ["ecc_only", "upgrade_needed"])),
      confidentiality_risk_count:
        Enum.count(sorted_findings, &(&1.exposure in ["confidentiality", "both"])),
      authentication_risk_count:
        Enum.count(sorted_findings, &(&1.exposure in ["authentication", "both"])),
      external_rail_count: Enum.count(sorted_findings, &(&1.boundary != "app_owned")),
      pqc_ready_count: length(ready),
      findings: sorted_findings,
      ready_packages: ready,
      playbook_slug: "ecc-pqc-migration-audit",
      verification_digest: digest,
      audited_at: DateTime.to_iso8601(now)
    }

    if include_cbom? do
      Map.put(base, :cbom, build_cyclonedx_cbom(evaluated, now))
    else
      base
    end
  end

  # --- Evaluation logic ---

  defp evaluate_package(pkg, package_names) do
    case find_rule(pkg) do
      nil -> []
      rule -> [build_evaluation(pkg, rule, package_names)]
    end
  end

  defp find_rule(pkg) do
    Enum.find(@rules, fn rule ->
      pkg.name in rule.match and (is_nil(pkg.ecosystem) or pkg.ecosystem in rule.ecosystems)
    end)
  end

  defp build_evaluation(pkg, rule, package_names) do
    {status, severity, note} = classify_pkg(pkg, rule, package_names)

    %{
      package: pkg.name,
      ecosystem: pkg.ecosystem || "unspecified",
      installed_version: pkg.version,
      role: rule.role,
      algorithms: rule.algorithms,
      status: status,
      severity: severity,
      exposure: Atom.to_string(rule.exposure),
      boundary: Atom.to_string(rule.boundary),
      remediation: note
    }
  end

  defp classify_pkg(pkg, %{quantum_status: :pqc_ready} = rule, _names) do
    {"pqc_ready", "info", rule.remediation <> version_suffix(pkg.version)}
  end

  defp classify_pkg(_pkg, %{quantum_status: :provider_dependent} = rule, package_names) do
    cond do
      MapSet.member?(package_names, "aws-lc-rs") and not MapSet.member?(package_names, "ring") ->
        {"pqc_ready", "info",
         "Paired with `aws-lc-rs` crypto provider; verify live X25519MLKEM768 negotiation with `patchbay_probe_crypto`."}

      MapSet.member?(package_names, "ring") ->
        {"upgrade_needed", "high",
         "Detected alongside `ring`, which does not support X25519MLKEM768. Switch rustls crypto provider to `aws-lc-rs`."}

      true ->
        {"review_provider", "medium", rule.remediation}
    end
  end

  defp classify_pkg(pkg, %{quantum_status: :version_gated, min_pqc_version: min} = rule, _names) do
    cond do
      is_nil(pkg.version) ->
        {"version_unpinned", "medium",
         "Unpinned version; pin `>= #{min}` to verify native post-quantum support. #{rule.remediation}"}

      StackCheck.compare_versions(pkg.version, min) in [:eq, :gt] ->
        {"pqc_ready", "info",
         "Pinned at `#{pkg.version}` (>= #{min}): native post-quantum primitives available."}

      true ->
        {"upgrade_needed", "high",
         "Pinned at `#{pkg.version}` (< #{min}): lacks native post-quantum primitives. #{rule.remediation}"}
    end
  end

  defp classify_pkg(_pkg, %{quantum_status: :ecc_only, boundary: :app_owned} = rule, _names) do
    sev = if rule.exposure == :both, do: "high", else: "medium"
    {"ecc_only", sev, rule.remediation}
  end

  defp classify_pkg(_pkg, %{quantum_status: :ecc_only} = rule, _names) do
    {"ecc_only", "medium", rule.remediation}
  end

  defp version_suffix(nil), do: ""
  defp version_suffix(v), do: " (pinned #{v})"

  defp severity_rank("high"), do: 0
  defp severity_rank("medium"), do: 1
  defp severity_rank(_), do: 2

  # --- CycloneDX 1.6 CBOM builder ---

  defp build_cyclonedx_cbom(evaluated, now) do
    library_components =
      Enum.map(evaluated, fn item ->
        ref =
          "pkg:#{item.ecosystem}/#{item.package}" <>
            if(item.installed_version, do: "@#{item.installed_version}", else: "")

        %{
          "type" => "library",
          "bom-ref" => ref,
          "name" => item.package,
          "version" => item.installed_version || "unpinned",
          "properties" => [
            %{"name" => "patchbay:crypto_role", "value" => item.role},
            %{"name" => "patchbay:quantum_status", "value" => item.status},
            %{"name" => "patchbay:exposure", "value" => item.exposure},
            %{"name" => "patchbay:boundary", "value" => item.boundary}
          ]
        }
      end)

    crypto_components =
      evaluated
      |> Enum.flat_map(& &1.algorithms)
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.map(fn alg ->
        %{
          "type" => "cryptographic-asset",
          "bom-ref" => "crypto:algorithm:#{String.downcase(alg)}",
          "name" => alg,
          "cryptoProperties" => %{
            "assetType" => "algorithm",
            "algorithmProperties" => algorithm_properties(alg)
          }
        }
      end)

    dependencies =
      Enum.map(evaluated, fn item ->
        ref =
          "pkg:#{item.ecosystem}/#{item.package}" <>
            if(item.installed_version, do: "@#{item.installed_version}", else: "")

        %{
          "ref" => ref,
          "dependsOn" => Enum.map(item.algorithms, &"crypto:algorithm:#{String.downcase(&1)}")
        }
      end)

    %{
      "bomFormat" => "CycloneDX",
      "specVersion" => "1.6",
      "version" => 1,
      "metadata" => %{
        "timestamp" => DateTime.to_iso8601(now),
        "tools" => %{
          "components" => [
            %{
              "type" => "application",
              "name" => "Patchbay CryptoAudit",
              "publisher" => "Regents Labs"
            }
          ]
        }
      },
      "components" => library_components ++ crypto_components,
      "dependencies" => dependencies
    }
  end

  defp algorithm_properties(alg) do
    cond do
      String.contains?(alg, "ML-KEM") or String.contains?(alg, "X-Wing") ->
        %{"primitive" => "kem", "classicalSecurityLevel" => 192, "nistQuantumSecurityLevel" => 3}

      String.contains?(alg, "ML-DSA") or String.contains?(alg, "SLH-DSA") ->
        %{
          "primitive" => "signature",
          "classicalSecurityLevel" => 192,
          "nistQuantumSecurityLevel" => 3
        }

      String.contains?(alg, "X25519") ->
        %{
          "primitive" => "key-agree",
          "classicalSecurityLevel" => 128,
          "nistQuantumSecurityLevel" => 0
        }

      String.contains?(alg, "TLS") ->
        %{
          "primitive" => "other",
          "classicalSecurityLevel" => 128,
          "nistQuantumSecurityLevel" => 0
        }

      true ->
        %{
          "primitive" => "signature",
          "classicalSecurityLevel" => 128,
          "nistQuantumSecurityLevel" => 0
        }
    end
  end

  defp normalize_entry(%{"name" => name} = map) when is_binary(name) do
    [
      %{
        ecosystem: map["ecosystem"],
        name: name |> String.trim() |> String.downcase(),
        version: map["version"]
      }
    ]
  end

  defp normalize_entry(name) when is_binary(name), do: StackCheck.parse_manifest(name)
  defp normalize_entry(_), do: []
end
