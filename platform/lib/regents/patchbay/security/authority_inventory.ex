defmodule Regents.Patchbay.Security.AuthorityInventory do
  @moduledoc """
  Read-only On-Chain Authority Exposure Inventory ("Embedded Firmware" check)
  for Safe treasuries, Autolaunch tokens, and Keyfleet fleets.

  Separates mutable contract authority (Safe owners, threshold, modules, guards,
  fallback handlers, and off-chain SIWA pairing) from immutable L1 execution
  boundaries (`secp256k1` transaction verification and `ecrecover` on Base /
  Ethereum), evaluates exposed-key blast radius against the signing quorum, and
  emits a deterministic `verification_digest` plus a concrete rotation rehearsal
  checklist.
  """

  @classifications ~w(supported_safe safe_1_of_1 eoa delegated_eoa unknown_contract split unsupported)
  @recovery_modes ~w(human_multisig timelock_guardian none)
  @zero_address "0x0000000000000000000000000000000000000000"

  @presets %{
    "autolaunch_safe" => %{
      label: "Autolaunch Treasury Safe (3-of-5 Base)",
      address: "0x1111111111111111111111111111111111111111",
      chain_id: 8453,
      classification: "supported_safe",
      owner_addresses: [
        "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
        "0xcccccccccccccccccccccccccccccccccccccccc",
        "0xdddddddddddddddddddddddddddddddddddddddd",
        "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
      ],
      threshold: 3,
      modules: [],
      guard: nil,
      fallback_handler: nil,
      exposed_owners: [
        "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      ],
      upgrade_admin: nil,
      recovery_mode: "human_multisig",
      app_auth_coupled?: false
    },
    "keyfleet_treasury" => %{
      label: "Keyfleet Classic Fleet Treasury (Key & Shard Governance)",
      address: "0x2222222222222222222222222222222222222222",
      chain_id: 8453,
      classification: "supported_safe",
      owner_addresses: [
        "0x1010101010101010101010101010101010101010",
        "0x2020202020202020202020202020202020202020",
        "0x3030303030303030303030303030303030303030"
      ],
      threshold: 2,
      modules: ["0x9999999999999999999999999999999999999999"],
      guard: "0x8888888888888888888888888888888888888888",
      fallback_handler: nil,
      exposed_owners: [
        "0x1010101010101010101010101010101010101010"
      ],
      upgrade_admin: "0x4040404040404040404040404040404040404040",
      recovery_mode: "timelock_guardian",
      app_auth_coupled?: false
    },
    "single_eoa_admin" => %{
      label: "Single Hot EOA Upgrade & Treasury Key",
      address: "0x3333333333333333333333333333333333333333",
      chain_id: 8453,
      classification: "eoa",
      owner_addresses: ["0x3333333333333333333333333333333333333333"],
      threshold: 1,
      modules: [],
      guard: nil,
      fallback_handler: nil,
      exposed_owners: ["0x3333333333333333333333333333333333333333"],
      upgrade_admin: "0x3333333333333333333333333333333333333333",
      recovery_mode: "none",
      app_auth_coupled?: true
    }
  }

  @doc "Return all built-in authority exposure presets."
  @spec presets() :: map()
  def presets, do: @presets

  @doc "Fetch a built-in authority exposure preset by name."
  @spec preset(String.t()) :: map() | nil
  def preset(name) when is_binary(name), do: Map.get(@presets, String.trim(name))
  def preset(_other), do: nil

  @doc """
  Analyze an on-chain treasury or governance authority configuration (or a
  named preset via `%{"preset" => "autolaunch_safe"}`) and return a
  deterministic exposure inventory, blast-radius check, and rehearsal steps.
  """
  @spec analyze(map()) :: {:ok, map()} | {:error, String.t()}
  def analyze(input) when is_map(input) do
    with {:ok, cfg} <- normalize_input(input) do
      owners = cfg.owner_addresses
      exposed = Enum.filter(cfg.exposed_owners, &(&1 in owners))
      unexposed_count = max(0, length(owners) - length(exposed))
      threshold = cfg.threshold
      compromise_reached? = threshold > 0 and length(exposed) >= threshold
      migration_quorum? = threshold > 0 and unexposed_count >= threshold

      quorum = %{
        owner_count: length(owners),
        threshold: threshold,
        exposed_owner_count: length(exposed),
        unexposed_owner_count: unexposed_count,
        compromise_quorum_reached?: compromise_reached?,
        migration_quorum_available?: migration_quorum?
      }

      checks = build_checks(cfg, quorum)
      verdict = compute_verdict(checks)
      surfaces = build_surfaces(cfg)
      steps = build_rehearsal_steps(cfg, quorum)

      canonical = %{
        address: cfg.address,
        chain_id: cfg.chain_id,
        classification: cfg.classification,
        owner_count: quorum.owner_count,
        threshold: quorum.threshold,
        exposed_owner_count: quorum.exposed_owner_count,
        module_count: length(cfg.modules),
        has_guard: not is_nil(cfg.guard),
        has_fallback_handler: not is_nil(cfg.fallback_handler),
        has_upgrade_admin: not is_nil(cfg.upgrade_admin),
        recovery_mode: cfg.recovery_mode,
        app_auth_coupled: cfg.app_auth_coupled?,
        verdict: Atom.to_string(verdict)
      }

      digest =
        "sha256:" <>
          (:crypto.hash(:sha256, Jason.encode!(canonical)) |> Base.encode16(case: :lower))

      {:ok,
       %{
         label: cfg.label,
         address: cfg.address,
         chain_id: cfg.chain_id,
         classification: cfg.classification,
         verdict: verdict,
         quorum_posture: quorum,
         surfaces: surfaces,
         checks: checks,
         rehearsal_steps: steps,
         playbook_slug: "ecc-pqc-migration-audit",
         verification_digest: digest,
         analyzed_at: DateTime.utc_now() |> DateTime.to_iso8601()
       }}
    end
  end

  def analyze(_other), do: {:error, "Provide an authority configuration map or preset name."}

  # --- Normalization ---

  defp normalize_input(input) do
    merged = merge_preset(input)
    classification = merged |> fetch_str(:classification, "supported_safe") |> String.downcase()
    recovery_mode = merged |> fetch_str(:recovery_mode, "human_multisig") |> String.downcase()
    address = normalize_optional_address(fetch_raw(merged, :address))
    owners = normalize_address_list(fetch_raw(merged, :owner_addresses))
    exposed = normalize_address_list(fetch_raw(merged, :exposed_owners))
    modules = normalize_address_list(fetch_raw(merged, :modules))
    threshold = normalize_int(fetch_raw(merged, :threshold), max(1, min(length(owners), 1)))
    chain_id = normalize_int(fetch_raw(merged, :chain_id), 8453)

    cond do
      classification not in @classifications ->
        {:error,
         "Unknown classification #{inspect(classification)}. Expected one of: #{Enum.join(@classifications, ", ")}."}

      recovery_mode not in @recovery_modes ->
        {:error,
         "Unknown recovery_mode #{inspect(recovery_mode)}. Expected one of: #{Enum.join(@recovery_modes, ", ")}."}

      address == :invalid ->
        {:error, "Invalid address format; expected 0x followed by 40 hex characters."}

      threshold < 0 or (owners != [] and threshold > length(owners)) ->
        {:error, "Threshold must be between 0 and the number of owners (#{length(owners)})."}

      true ->
        {:ok,
         %{
           label: fetch_str(merged, :label, "Custom Treasury Authority"),
           address: address,
           chain_id: chain_id,
           classification: classification,
           owner_addresses: owners,
           threshold: threshold,
           modules: modules,
           guard: normalize_optional_address(fetch_raw(merged, :guard)),
           fallback_handler: normalize_optional_address(fetch_raw(merged, :fallback_handler)),
           exposed_owners: exposed,
           upgrade_admin: normalize_optional_address(fetch_raw(merged, :upgrade_admin)),
           recovery_mode: recovery_mode,
           app_auth_coupled?: truthy?(fetch_raw(merged, :app_auth_coupled?))
         }}
    end
  end

  defp merge_preset(input) do
    case fetch_raw(input, :preset) do
      name when is_binary(name) and name != "" ->
        case preset(name) do
          nil -> input
          base -> Map.merge(base, stringify_drop_blank(input))
        end

      _ ->
        input
    end
  end

  defp stringify_drop_blank(input) do
    input
    |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
    |> Map.new(fn {k, v} -> {to_atom_or_key(k), v} end)
  end

  @known_keys %{
    "label" => :label,
    "address" => :address,
    "chain_id" => :chain_id,
    "classification" => :classification,
    "owner_addresses" => :owner_addresses,
    "threshold" => :threshold,
    "modules" => :modules,
    "guard" => :guard,
    "fallback_handler" => :fallback_handler,
    "exposed_owners" => :exposed_owners,
    "upgrade_admin" => :upgrade_admin,
    "recovery_mode" => :recovery_mode,
    "app_auth_coupled" => :app_auth_coupled?,
    "app_auth_coupled?" => :app_auth_coupled?
  }

  defp to_atom_or_key(key) when is_atom(key), do: key
  defp to_atom_or_key(key) when is_binary(key), do: Map.get(@known_keys, key, key)

  # --- Checks & Surfaces ---

  defp build_checks(cfg, quorum) do
    [
      classification_check(cfg.classification, quorum),
      exposed_quorum_check(quorum),
      modules_check(cfg.modules, cfg.guard),
      fallback_check(cfg.fallback_handler),
      upgrade_admin_check(cfg.upgrade_admin),
      app_auth_check(cfg.app_auth_coupled?),
      recovery_check(cfg.recovery_mode),
      l1_boundary_check(cfg.chain_id)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp classification_check("eoa", _q) do
    %{
      level: :fail,
      code: "single_eoa_authority",
      message:
        "Authority is a single EOA: one compromised secp256k1 key yields immediate total control with no multisig threshold or on-chain key rotation."
    }
  end

  defp classification_check("delegated_eoa", _q) do
    %{
      level: :fail,
      code: "delegated_eoa_authority",
      message:
        "Authority is an EIP-7702 delegated EOA: the underlying secp256k1 root key can still re-delegate or override contract logic."
    }
  end

  defp classification_check("safe_1_of_1", _q) do
    %{
      level: :warn,
      code: "safe_1_of_1_no_quorum",
      message:
        "1-of-1 Safe allows swapping the owner, but a single exposed secp256k1 key still grants immediate execution without co-signers."
    }
  end

  defp classification_check("supported_safe", %{owner_count: n, threshold: t}) when t >= 2 do
    %{
      level: :pass,
      code: "multisig_safe_quorum",
      message:
        "Safe multisig enforces a #{t}-of-#{n} quorum, enabling owner rotation and guard policies without migrating funds to a new address."
    }
  end

  defp classification_check(other, _q) do
    %{
      level: :warn,
      code: "non_standard_treasury_type",
      message:
        "Treasury classification is `#{other}`; verify owner rotation and emergency pause authority manually."
    }
  end

  defp exposed_quorum_check(%{
         compromise_quorum_reached?: true,
         exposed_owner_count: exp,
         threshold: t
       }) do
    %{
      level: :fail,
      code: "exposed_owners_meet_threshold",
      message:
        "#{exp} owner key(s) have exposed public keys (signed on-chain or hot), meeting or exceeding the #{t}-signature threshold. Rotate cold unexposed signers before any ECC break."
    }
  end

  defp exposed_quorum_check(%{migration_quorum_available?: true, unexposed_owner_count: unexp}) do
    %{
      level: :pass,
      code: "unexposed_rotation_quorum_ready",
      message:
        "#{unexp} unexposed owner key(s) remain available—enough to reach quorum and rotate compromised signers cleanly."
    }
  end

  defp exposed_quorum_check(%{owner_count: n, exposed_owner_count: exp, threshold: t}) do
    %{
      level: :warn,
      code: "exposed_owners_below_rotation_margin",
      message:
        "#{exp} of #{n} owners are exposed against a #{t}-of-#{n} threshold: exposed keys do not meet quorum alone, but unexposed keys alone cannot rotate them without coordination."
    }
  end

  defp modules_check([], _guard), do: nil

  defp modules_check(modules, guard) do
    guard_note =
      if guard,
        do: "Guard #{short_addr(guard)} is set, but Safe modules bypass transaction guards.",
        else: "No Safe guard is configured."

    %{
      level: :warn,
      code: "safe_modules_enabled",
      message:
        "#{length(modules)} Safe module(s) enabled. Modules execute outside normal owner threshold checks; audit every module's signer authority. #{guard_note}"
    }
  end

  defp fallback_check(nil), do: nil

  defp fallback_check(handler) do
    %{
      level: :warn,
      code: "safe_fallback_handler_set",
      message:
        "Fallback handler #{short_addr(handler)} is configured; verify ERC-1271 signature validation does not accept retired keys."
    }
  end

  defp upgrade_admin_check(nil), do: nil

  defp upgrade_admin_check(admin) do
    %{
      level: :warn,
      code: "upgrade_admin_present",
      message:
        "Separate proxy/upgrade admin #{short_addr(admin)} exists. Ensure it sits behind a timelocked multisig, never a single hot EOA."
    }
  end

  defp app_auth_check(true) do
    %{
      level: :fail,
      code: "app_auth_coupled_to_wallet",
      message:
        "Off-chain agent authentication (SIWA / API signing) shares keys with on-chain treasury authority. Separate off-chain ML-DSA-65 identity from L1 wallet keys."
    }
  end

  defp app_auth_check(false) do
    %{
      level: :pass,
      code: "app_auth_decoupled",
      message: "Off-chain agent identity is decoupled from on-chain treasury signing keys."
    }
  end

  defp recovery_check("none") do
    %{
      level: :warn,
      code: "no_recovery_mode",
      message: "No out-of-band human multisig or timelock guardian recovery path is documented."
    }
  end

  defp recovery_check(mode) do
    %{
      level: :pass,
      code: "recovery_mode_configured",
      message: "Out-of-band recovery mode documented: `#{mode}`."
    }
  end

  defp l1_boundary_check(chain_id) do
    %{
      level: :pass,
      code: "l1_secp256k1_boundary_documented",
      message:
        "Embedded-firmware boundary recorded: chain #{chain_id} transaction settlement remains bound to secp256k1/ecrecover until protocol-level AA/PQC upgrades ship."
    }
  end

  defp build_surfaces(cfg) do
    [
      %{
        surface: "Owner & Threshold Policy",
        boundary: "mutable_in_contract",
        algorithm: "secp256k1 / ERC-1271",
        owner_controlled?: cfg.classification in ["supported_safe", "safe_1_of_1"],
        note: "Can rotate owners, raise threshold, or adopt ERC-4337/PQC validator modules."
      },
      %{
        surface: "Safe Modules & Guard",
        boundary: "mutable_in_contract",
        algorithm: "contract_logic",
        owner_controlled?: cfg.classification in ["supported_safe", "safe_1_of_1"],
        note:
          "#{length(cfg.modules)} module(s), guard #{if cfg.guard, do: "active", else: "none"}."
      },
      %{
        surface: "Off-Chain Agent Auth (SIWA / API)",
        boundary: "mutable_in_contract",
        algorithm: if(cfg.app_auth_coupled?, do: "coupled_secp256k1", else: "decoupled_siwa_v3"),
        owner_controlled?: true,
        note: "Upgradeable today to SIWA v3 hybrid ECC + ML-DSA-65 with human recovery."
      },
      %{
        surface: "Base / EVM L1 Transaction Execution",
        boundary: "embedded_firmware_l1_bound",
        algorithm: "secp256k1 (ecrecover)",
        owner_controlled?: false,
        note:
          "Immutable at the application layer on chain #{cfg.chain_id}; mitigate via cold unexposed signers, working-balance caps, and AA PQC verifiers as L1/L2 support matures."
      }
    ]
  end

  defp build_rehearsal_steps(cfg, quorum) do
    steps = []

    steps =
      if cfg.classification in ["eoa", "delegated_eoa", "safe_1_of_1"],
        do: steps ++ ["Migrate treasury & admin control to a >= 2-of-3 Safe multisig."],
        else: steps

    steps =
      if quorum.compromise_quorum_reached? or not quorum.migration_quorum_available?,
        do:
          steps ++
            [
              "Pre-provision cold, never-signed-on-chain owner keys so unexposed signers strictly outnumber threshold."
            ],
        else: steps

    steps =
      if cfg.app_auth_coupled?,
        do:
          steps ++
            [
              "Decouple off-chain agent auth (SIWA) from treasury keys and prepare ML-DSA-65 co-signing enrollment."
            ],
        else: steps

    steps =
      if cfg.modules != [],
        do:
          steps ++
            [
              "Audit every enabled Safe module and remove unused modules that bypass threshold and guard checks."
            ],
        else: steps

    steps ++
      [
        "Keep working balances small in hot execution contracts and rehearse an owner-rotation transaction on testnet/fork.",
        "Record this inventory's verification_digest alongside Patchbay's TLS & CBOM digests in your migration log."
      ]
  end

  defp compute_verdict(checks) do
    cond do
      Enum.any?(checks, &(&1.level == :fail)) -> :fail
      Enum.any?(checks, &(&1.level == :warn)) -> :warn
      true -> :pass
    end
  end

  # --- Input helpers ---

  defp fetch_raw(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, Atom.to_string(key))
    end
  end

  defp fetch_str(map, key, default) do
    case fetch_raw(map, key) do
      val when is_binary(val) ->
        trimmed = String.trim(val)
        if trimmed == "", do: default, else: trimmed

      _ ->
        default
    end
  end

  defp normalize_int(val, _default) when is_integer(val), do: val

  defp normalize_int(val, default) when is_binary(val) do
    case Integer.parse(String.trim(val)) do
      {int, ""} -> int
      _ -> default
    end
  end

  defp normalize_int(_val, default), do: default

  defp normalize_optional_address(nil), do: nil
  defp normalize_optional_address(""), do: nil

  defp normalize_optional_address(addr) when is_binary(addr) do
    down = addr |> String.trim() |> String.downcase()

    cond do
      down == "" or down == @zero_address -> nil
      Regex.match?(~r/\A0x[0-9a-f]{40}\z/, down) -> down
      true -> :invalid
    end
  end

  defp normalize_optional_address(_), do: :invalid

  defp normalize_address_list(list) when is_list(list) do
    list
    |> Enum.flat_map(fn item ->
      case normalize_optional_address(item) do
        addr when is_binary(addr) -> [addr]
        _ -> []
      end
    end)
    |> Enum.uniq()
  end

  defp normalize_address_list(text) when is_binary(text) do
    text
    |> String.split(~r/[\s,;]+/, trim: true)
    |> normalize_address_list()
  end

  defp normalize_address_list(_), do: []

  defp short_addr(<<"0x", a::binary-size(4), _rest::binary-size(32), b::binary-size(4)>>),
    do: "0x#{a}…#{b}"

  defp short_addr(other), do: other

  defp truthy?(true), do: true
  defp truthy?("true"), do: true
  defp truthy?("1"), do: true
  defp truthy?(_), do: false
end
