defmodule Regents.Patchbay.Security.StackCheck do
  @moduledoc """
  Version-accurate dependency security checker for Patchbay.

  Parses exact pinned versions from 12+ real-world manifest, lockfile, and SBOM
  formats (`package.json`, `package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`
  v1/Berry, `composer.json`, `composer.lock`, `mix.lock`, `Cargo.toml`,
  `Cargo.lock`, `requirements.txt`, `uv.lock`, `poetry.lock`, `go.mod`, `go.sum`,
  `Gemfile.lock`, CycloneDX JSON SBOM, SPDX JSON SBOM, or `name@version` lists)
  up to 2 MB / 1,500 packages and evaluates them against Patchbay's live
  mirrored `cve.now` active criticals (using OSV `introduced` / `fixed` /
  `last_affected` version ranges) plus curated security briefings.

  When a lockfile pins a patched version (`version >= fixed` or outside all
  affected ranges), the package is cleared as patched rather than falsely
  flagged.
  """

  alias Regents.Patchbay.Forum
  alias Regents.Patchbay.Forum.PostAddress
  alias Regents.Patchbay.Incidents

  @max_input_bytes 2 * 1024 * 1024
  @max_packages 1_500
  @max_cves_scanned 250

  @purl_ecosystems %{
    "npm" => "npm",
    "pypi" => "pypi",
    "composer" => "packagist",
    "packagist" => "packagist",
    "cargo" => "cargo",
    "golang" => "go",
    "go" => "go",
    "hex" => "hex",
    "gem" => "rubygems",
    "rubygems" => "rubygems",
    "maven" => "maven",
    "nuget" => "nuget",
    "deb" => "debian",
    "apk" => "alpine"
  }

  @type parsed_package :: %{
          ecosystem: String.t() | nil,
          name: String.t(),
          version: String.t() | nil
        }

  @doc """
  Parse raw manifest text or a structured package list and evaluate against
  Patchbay's active critical CVE mirror and incident briefings.
  """
  @spec check(String.t() | [map()]) :: {:ok, map()} | {:error, String.t()}
  def check(input) when is_binary(input) do
    if byte_size(input) > @max_input_bytes do
      {:error, "Manifest text exceeds 2 MB limit."}
    else
      packages = parse_manifest(input)

      if packages == [] do
        {:error,
         "No package names detected. Paste or upload package.json, package-lock.json, pnpm-lock.yaml, yarn.lock, composer.lock, mix.lock, requirements.txt, uv.lock, poetry.lock, Cargo.toml, Cargo.lock, go.mod, go.sum, Gemfile.lock, CycloneDX/SPDX JSON SBOM, or a comma/line-separated list of packages."}
      else
        {:ok, evaluate(packages, load_cves(), Incidents.all())}
      end
    end
  end

  def check(packages) when is_list(packages) do
    normalized =
      packages
      |> Enum.flat_map(&normalize_package_entry/1)
      |> dedupe_packages()
      |> Enum.take(@max_packages)

    if normalized == [] do
      {:error, "Provide at least one package name to check."}
    else
      {:ok, evaluate(normalized, load_cves(), Incidents.all())}
    end
  end

  def check(_other), do: {:error, "Provide manifest text or a list of packages."}

  @doc """
  Pure evaluator: match parsed packages against a list of CVE posts and curated
  briefings. Exposed for deterministic conformance benchmarking without DB I/O.
  """
  @spec evaluate([parsed_package()], [map()], [map()]) :: map()
  def evaluate(packages, cves, briefings \\ []) when is_list(packages) and is_list(cves) do
    {cve_matches, cleared} = match_cves(cves, packages)
    briefing_matches = match_briefings(briefings, packages)

    matches =
      (cve_matches ++ briefing_matches)
      |> Enum.sort_by(&{not &1.exploited, -(&1.score || 0.0)})

    cleared = Enum.uniq_by(cleared, &{&1.cve_id, &1.package, &1.installed_version})

    %{
      checked_packages: packages,
      package_count: length(packages),
      versioned_package_count: Enum.count(packages, &(not is_nil(&1.version))),
      cves_scanned: length(cves),
      match_count: length(matches),
      kev_match_count: Enum.count(matches, & &1.exploited),
      unfixed_match_count: Enum.count(matches, &(not &1.fix_available)),
      cleared_count: length(cleared),
      cleared_packages: cleared,
      matches: matches
    }
  end

  @doc "Extract normalized `{ecosystem, name, version}` entries from common manifest, lockfile, and SBOM formats."
  @spec parse_manifest(String.t()) :: [parsed_package()]
  def parse_manifest(text) when is_binary(text) do
    trimmed = String.trim(text)

    trimmed
    |> dispatch_manifest_parser()
    |> dedupe_packages()
    |> Enum.take(@max_packages)
  end

  defp dispatch_manifest_parser(""), do: []

  defp dispatch_manifest_parser(trimmed) do
    parsers = [
      {&String.starts_with?(&1, "{"), &parse_json_manifest/1},
      {&String.contains?(&1, "{:hex,"), &parse_mix_lock/1},
      {&String.contains?(&1, "[[package]]"), &parse_toml_lock/1},
      {&pnpm_lock?/1, &parse_pnpm_lock/1},
      {&yarn_lock?/1, &parse_yarn_lock/1},
      {&gemfile_lock?/1, &parse_gemfile_lock/1},
      {&String.contains?(&1, "[dependencies]"), &parse_cargo_toml/1},
      {&go_mod?/1, &parse_go_mod/1},
      {&go_sum?/1, &parse_go_sum/1}
    ]

    case Enum.find(parsers, fn {match?, _parser} -> match?.(trimmed) end) do
      {_match?, parser} -> parser.(trimmed)
      nil -> parse_plain_or_requirements(trimmed)
    end
  end

  defp pnpm_lock?(text),
    do:
      String.contains?(text, "lockfileVersion:") and
        (String.contains?(text, "\npackages:") or String.contains?(text, "\nsnapshots:"))

  defp yarn_lock?(text),
    do:
      String.contains?(text, "yarn lockfile v1") or
        (String.contains?(text, "__metadata:") and String.contains?(text, "resolution:"))

  defp gemfile_lock?(text),
    do: String.contains?(text, "GEM\n") and String.contains?(text, "specs:\n")

  defp go_mod?(text),
    do: String.contains?(text, "module ") and String.contains?(text, "require")

  defp go_sum?(text),
    do: Regex.match?(~r/^\S+\s+v[0-9][^\s]*(?:\/go\.mod)?\s+h1:/m, text)

  @doc """
  Determine whether `installed_version` falls inside a structured package entry's
  vulnerable ranges/versions. Returns `:vulnerable`, `:patched`, or `:unknown`.
  """
  @spec evaluate_package_version(String.t() | nil, map()) :: :vulnerable | :patched | :unknown
  def evaluate_package_version(nil, _sp), do: :unknown

  def evaluate_package_version(installed_version, sp) when is_binary(installed_version) do
    ranges = List.wrap(sp["ranges"]) |> Enum.filter(&is_map/1)
    explicit_versions = List.wrap(sp["versions"]) |> Enum.filter(&is_binary/1)
    fixed_versions = List.wrap(sp["fixed"]) |> Enum.filter(&is_binary/1)

    cond do
      ranges != [] ->
        if Enum.any?(ranges, &version_in_range?(installed_version, &1)),
          do: :vulnerable,
          else: :patched

      explicit_versions != [] ->
        if Enum.any?(explicit_versions, &(compare_versions(installed_version, &1) == :eq)),
          do: :vulnerable,
          else: :patched

      fixed_versions != [] ->
        evaluate_against_fixed_list(installed_version, fixed_versions)

      true ->
        :unknown
    end
  end

  @doc """
  Compare two SemVer or dotted-numeric version strings (`:lt`, `:eq`, or `:gt`).
  """
  @spec compare_versions(String.t(), String.t()) :: :lt | :eq | :gt
  def compare_versions(a, b) when is_binary(a) and is_binary(b) do
    {nums_a, pre_a} = parse_version_tuple(a)
    {nums_b, pre_b} = parse_version_tuple(b)

    case compare_numeric_lists(nums_a, nums_b) do
      :eq -> compare_prerelease(pre_a, pre_b)
      other -> other
    end
  end

  # --- JSON Manifest & SBOM parsers ---

  defp parse_json_manifest(text) do
    case Jason.decode(text) do
      {:ok, %{"bomFormat" => "CycloneDX"} = map} ->
        parse_cyclonedx_sbom(map)

      {:ok, %{"spdxVersion" => _} = map} ->
        parse_spdx_sbom(map)

      {:ok, %{"lockfileVersion" => _} = map} ->
        parse_package_lock_json(map)

      {:ok, %{"packages" => pkgs} = map} when is_list(pkgs) ->
        parse_composer_lock(map)

      {:ok, %{"require" => req} = map} when is_map(req) ->
        parse_composer_json(map)

      {:ok, %{} = map} ->
        parse_package_json(map)

      _ ->
        parse_plain_or_requirements(text)
    end
  end

  defp parse_cyclonedx_sbom(map) do
    map
    |> Map.get("components", [])
    |> List.wrap()
    |> Enum.flat_map(&cyclonedx_component_to_pkg/1)
  end

  defp cyclonedx_component_to_pkg(%{"purl" => purl} = comp) when is_binary(purl) do
    case parse_purl(purl) do
      {:ok, pkg} ->
        ver = pkg.version || clean_version(comp["version"])
        [%{pkg | version: ver}]

      :error ->
        fallback_sbom_component(comp["name"], comp["version"])
    end
  end

  defp cyclonedx_component_to_pkg(%{"name" => name} = comp),
    do: fallback_sbom_component(name, comp["version"])

  defp cyclonedx_component_to_pkg(_other), do: []

  defp parse_spdx_sbom(map) do
    map
    |> Map.get("packages", [])
    |> List.wrap()
    |> Enum.flat_map(&spdx_package_to_pkg/1)
  end

  defp spdx_package_to_pkg(%{} = pkg) do
    purl =
      pkg
      |> Map.get("externalRefs", [])
      |> List.wrap()
      |> Enum.find_value(fn
        %{"referenceType" => "purl", "referenceLocator" => loc} when is_binary(loc) -> loc
        _ -> nil
      end)

    case purl && parse_purl(purl) do
      {:ok, parsed} ->
        ver = parsed.version || clean_version(pkg["versionInfo"])
        [%{parsed | version: ver}]

      _ ->
        fallback_sbom_component(pkg["name"], pkg["versionInfo"])
    end
  end

  defp spdx_package_to_pkg(_other), do: []

  defp fallback_sbom_component(name, version) when is_binary(name) and name != "" do
    [%{ecosystem: nil, name: String.downcase(String.trim(name)), version: clean_version(version)}]
  end

  defp fallback_sbom_component(_name, _version), do: []

  defp parse_purl("pkg:" <> rest) do
    without_qualifiers = rest |> String.split(["?", "#"], parts: 2) |> hd()

    case String.split(without_qualifiers, "/", parts: 2) do
      [raw_type, remainder] when remainder != "" ->
        eco = Map.get(@purl_ecosystems, String.downcase(raw_type), String.downcase(raw_type))
        {raw_name, raw_ver} = split_purl_version(remainder)
        name = raw_name |> URI.decode() |> String.trim() |> String.downcase()

        if name != "",
          do: {:ok, %{ecosystem: eco, name: name, version: clean_version(raw_ver)}},
          else: :error

      _ ->
        :error
    end
  end

  defp parse_purl(_other), do: :error

  defp split_purl_version(remainder) do
    case String.split(remainder, "@", parts: 2) do
      [name, ver] -> {name, URI.decode(ver)}
      [name] -> {name, nil}
    end
  end

  defp parse_package_lock_json(map) do
    from_packages =
      case map["packages"] do
        %{} = pkgs ->
          for {path, info} <- pkgs,
              is_map(info),
              String.contains?(path, "node_modules/") do
            name =
              path
              |> String.split("node_modules/")
              |> List.last()
              |> String.downcase()

            %{ecosystem: "npm", name: name, version: clean_version(info["version"])}
          end

        _ ->
          []
      end

    from_deps =
      case map["dependencies"] do
        %{} = deps ->
          for {name, info} <- deps, is_map(info) do
            %{
              ecosystem: "npm",
              name: String.downcase(name),
              version: clean_version(info["version"])
            }
          end

        _ ->
          []
      end

    from_packages ++ from_deps
  end

  defp parse_package_json(map) do
    sections = [
      map["dependencies"] || %{},
      map["devDependencies"] || %{},
      map["peerDependencies"] || %{},
      map["optionalDependencies"] || %{}
    ]

    for section when is_map(section) <- sections, {name, spec} <- section do
      %{ecosystem: "npm", name: String.downcase(name), version: clean_version(spec)}
    end
  end

  defp parse_composer_lock(map) do
    pkgs = List.wrap(map["packages"]) ++ List.wrap(map["packages-dev"])

    for %{"name" => name} = pkg <- pkgs, is_binary(name) do
      %{
        ecosystem: "packagist",
        name: String.downcase(String.trim(name)),
        version: clean_version(pkg["version"])
      }
    end
  end

  defp parse_composer_json(map) do
    sections = [map["require"] || %{}, map["require-dev"] || %{}]

    for section when is_map(section) <- sections,
        {name, spec} <- section,
        name != "php" and not String.starts_with?(name, "ext-") do
      %{
        ecosystem: "packagist",
        name: String.downcase(String.trim(name)),
        version: clean_version(spec)
      }
    end
  end

  # --- YAML / Lockfile parsers (pnpm, yarn, Gemfile, mix, Cargo, uv, poetry, Go) ---

  defp parse_pnpm_lock(text) do
    # Matches pnpm v6/v9 keys under packages: or snapshots:
    # e.g. "  '/@scope/pkg@1.2.3':", "  next@15.1.0(react@19.0.0):", "  /lodash/4.17.21:"
    text
    |> String.split(~r/\r?\n/)
    |> Enum.flat_map(&parse_pnpm_line/1)
  end

  defp parse_pnpm_line(line) do
    case Regex.run(
           ~r/^\s{2,4}['"]?\/?((?:@[^@\/\s'"]+\/)?[^@\/\s'":(]+)[@\/]([0-9][^'":(\s]*)[^:]*:\s*$/,
           line
         ) do
      [_, name, ver] ->
        case clean_version(ver) do
          nil -> []
          cleaned -> [%{ecosystem: "npm", name: String.downcase(name), version: cleaned}]
        end

      _ ->
        []
    end
  end

  defp parse_yarn_lock(text) do
    text
    |> String.split(~r/\r?\n\r?\n+/)
    |> Enum.flat_map(&parse_yarn_block/1)
  end

  defp parse_yarn_block(block) do
    trimmed = String.trim(block)

    if trimmed == "" or String.starts_with?(trimmed, "#") or
         String.starts_with?(trimmed, "__metadata:") do
      []
    else
      header = trimmed |> String.split(~r/\r?\n/, parts: 2) |> hd()

      with name when is_binary(name) <- extract_yarn_name(header),
           ver when is_binary(ver) <- extract_yarn_version(trimmed) do
        [%{ecosystem: "npm", name: name, version: ver}]
      else
        _ -> []
      end
    end
  end

  defp extract_yarn_name(header) do
    first_spec =
      header
      |> String.trim_trailing(":")
      |> String.split(",", parts: 2)
      |> hd()
      |> String.trim()
      |> String.trim("\"")
      |> String.trim("'")

    case Regex.run(~r/\A((?:@[^@\/\s]+\/)?[^@\s]+)@/, first_spec) do
      [_, name] -> String.downcase(name)
      _ -> nil
    end
  end

  defp extract_yarn_version(block) do
    case Regex.run(~r/^\s+version(?:\s+"([^"]+)"|:\s*([^\s"]+))/m, block) do
      [_, v1] when v1 != "" -> clean_version(v1)
      [_, "", v2] -> clean_version(v2)
      _ -> nil
    end
  end

  defp parse_gemfile_lock(text) do
    Regex.scan(~r/^\s{4}([a-zA-Z0-9._-]+)\s+\(([0-9][^)\s]*)\)\s*$/m, text)
    |> Enum.map(fn [_, name, ver] ->
      %{ecosystem: "rubygems", name: String.downcase(name), version: clean_version(ver)}
    end)
  end

  defp parse_mix_lock(text) do
    Regex.scan(~r/"([a-z0-9_]+)":\s*\{:hex,\s*:[a-z0-9_]+,\s*"([^"]+)"/i, text)
    |> case do
      [] ->
        Regex.scan(~r/"([a-z0-9_]+)":\s*\{:hex,/i, text)
        |> Enum.map(fn [_, name] ->
          %{ecosystem: "hex", name: String.downcase(name), version: nil}
        end)

      matches ->
        Enum.map(matches, fn [_, name, ver] ->
          %{ecosystem: "hex", name: String.downcase(name), version: clean_version(ver)}
        end)
    end
  end

  defp parse_toml_lock(text) do
    ecosystem = toml_lock_ecosystem(text)

    text
    |> String.split(~r/^\s*\[\[package\]\]\s*$/m)
    |> Enum.drop(1)
    |> Enum.flat_map(&parse_toml_package_block(&1, ecosystem))
  end

  defp toml_lock_ecosystem(text) do
    python_markers = [
      "requires-python",
      "pypi.org",
      "python-versions",
      "[metadata]\nlock-version"
    ]

    if Enum.any?(python_markers, &String.contains?(text, &1)), do: "pypi", else: "cargo"
  end

  defp parse_toml_package_block(block, ecosystem) do
    name = regex_first_capture(~r/^\s*name\s*=\s*"([^"]+)"/m, block)
    version = regex_first_capture(~r/^\s*version\s*=\s*"([^"]+)"/m, block) |> clean_version()

    case name && String.downcase(String.trim(name)) do
      n when is_binary(n) and n != "" -> [%{ecosystem: ecosystem, name: n, version: version}]
      _ -> []
    end
  end

  defp regex_first_capture(pattern, text) do
    case Regex.run(pattern, text) do
      [_, value] -> value
      _ -> nil
    end
  end

  defp parse_cargo_toml(text) do
    string_deps =
      Regex.scan(~r/^\s*([a-zA-Z0-9_-]+)\s*=\s*"([^"]+)"/m, text)
      |> Enum.map(fn [_, name, ver] -> {String.downcase(name), clean_version(ver)} end)

    table_deps =
      Regex.scan(~r/^\s*([a-zA-Z0-9_-]+)\s*=\s*\{[^}]*version\s*=\s*"([^"]+)"/m, text)
      |> Enum.map(fn [_, name, ver] -> {String.downcase(name), clean_version(ver)} end)

    meta_keys =
      ~w(name version edition authors license description repository homepage documentation readme)

    (string_deps ++ table_deps)
    |> Enum.reject(fn {name, _ver} -> name in meta_keys end)
    |> Enum.map(fn {name, ver} -> %{ecosystem: "cargo", name: name, version: ver} end)
  end

  defp parse_go_mod(text) do
    Regex.scan(~r/^\s*([a-z0-9.-]+\/[a-z0-9._\/-]+)\s+(v[0-9][^\s]*)/im, text)
    |> Enum.map(fn [_, mod, ver] ->
      %{ecosystem: "go", name: String.downcase(mod), version: clean_version(ver)}
    end)
  end

  defp parse_go_sum(text) do
    Regex.scan(~r/^([a-z0-9.-]+\/[a-z0-9._\/-]+)\s+(v[0-9][^\s\/]*)(?:\/go\.mod)?\s+h1:/im, text)
    |> Enum.map(fn [_, mod, ver] ->
      %{ecosystem: "go", name: String.downcase(mod), version: clean_version(ver)}
    end)
  end

  defp parse_plain_or_requirements(text) do
    text
    |> String.split(~r/[\r\n,]+/, trim: true)
    |> Enum.flat_map(&parse_manifest_line/1)
    |> Enum.reject(&(&1.name == ""))
  end

  defp parse_manifest_line(line) do
    cleaned = line |> String.split("#", parts: 2) |> hd() |> String.trim()

    cond do
      cleaned == "" or String.starts_with?(cleaned, "-") -> []
      String.contains?(cleaned, ":") -> parse_ecosystem_line(cleaned)
      true -> parse_bare_line(cleaned)
    end
  end

  defp parse_ecosystem_line(cleaned) do
    case String.split(cleaned, ":", parts: 2) do
      [eco, rest] ->
        {name, ver} = split_name_and_version(rest)
        wrap_parsed(String.downcase(String.trim(eco)), name, ver)

      _ ->
        []
    end
  end

  defp parse_bare_line(cleaned) do
    {name, ver} = split_name_and_version(cleaned)
    wrap_parsed(nil, name, ver)
  end

  defp wrap_parsed(_eco, "", _ver), do: []
  defp wrap_parsed(eco, name, ver), do: [%{ecosystem: eco, name: name, version: ver}]

  defp split_name_and_version(raw) do
    trimmed = String.trim(raw)

    cond do
      Regex.match?(~r/\A(@[^@\s\/]+\/[^@\s=<>!~]+)@([^\s,;]+)\z/, trimmed) ->
        [_, name, ver] = Regex.run(~r/\A(@[^@\s\/]+\/[^@\s=<>!~]+)@([^\s,;]+)\z/, trimmed)
        {String.downcase(name), clean_version(ver)}

      Regex.match?(~r/\A([^@\s=<>!~]+)@([^\s,;]+)\z/, trimmed) ->
        [_, name, ver] = Regex.run(~r/\A([^@\s=<>!~]+)@([^\s,;]+)\z/, trimmed)
        {String.downcase(name), clean_version(ver)}

      Regex.match?(
        ~r/\A([a-zA-Z0-9._\/@-]+)(?:\[[^\]]+\])?\s*(?:===|==|~=|>=|<=|=)\s*([^\s,;]+)/,
        trimmed
      ) ->
        [_, name, ver] =
          Regex.run(
            ~r/\A([a-zA-Z0-9._\/@-]+)(?:\[[^\]]+\])?\s*(?:===|==|~=|>=|<=|=)\s*([^\s,;]+)/,
            trimmed
          )

        {String.downcase(name), clean_version(ver)}

      Regex.match?(~r/\A([a-zA-Z0-9._\/@-]+)\s+(v?[0-9][^\s,;]*)\z/, trimmed) ->
        [_, name, ver] = Regex.run(~r/\A([a-zA-Z0-9._\/@-]+)\s+(v?[0-9][^\s,;]*)\z/, trimmed)
        {String.downcase(name), clean_version(ver)}

      true ->
        {clean_pkg_name(trimmed), nil}
    end
  end

  defp clean_pkg_name(raw) do
    raw
    |> String.trim()
    |> String.split(~r/[=<>!~;\[\s]/, parts: 2)
    |> hd()
    |> String.trim()
    |> String.downcase()
  end

  defp clean_version(ver) when is_binary(ver) do
    trimmed =
      ver
      |> String.trim()
      |> String.replace(~r/\A[\^~v=<>!\s]+/, "")
      |> String.split(~r/[\s,|]+/, parts: 2)
      |> hd()
      |> String.trim()

    if Regex.match?(
         ~r/\A[0-9]+(?:\.[0-9]+)*(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?\z/,
         trimmed
       ),
       do: trimmed,
       else: nil
  end

  defp clean_version(_other), do: nil

  defp normalize_package_entry(%{"name" => name} = entry) when is_binary(name) do
    {cleaned, inline_ver} = split_name_and_version(name)
    eco = if is_binary(entry["ecosystem"]), do: String.downcase(String.trim(entry["ecosystem"]))
    ver = clean_version(entry["version"]) || inline_ver
    if cleaned == "", do: [], else: [%{ecosystem: eco, name: cleaned, version: ver}]
  end

  defp normalize_package_entry(%{name: name} = entry) when is_binary(name) do
    {cleaned, inline_ver} = split_name_and_version(name)
    eco = if is_binary(entry[:ecosystem]), do: String.downcase(String.trim(entry[:ecosystem]))
    ver = clean_version(entry[:version]) || inline_ver
    if cleaned == "", do: [], else: [%{ecosystem: eco, name: cleaned, version: ver}]
  end

  defp normalize_package_entry(name) when is_binary(name) do
    parse_plain_or_requirements(name)
  end

  defp normalize_package_entry(_other), do: []

  defp dedupe_packages(packages) do
    packages
    |> Enum.reduce(%{}, fn pkg, acc ->
      Map.update(acc, {pkg.ecosystem, pkg.name}, pkg, &prefer_versioned(&1, pkg))
    end)
    |> Map.values()
  end

  defp prefer_versioned(%{version: nil}, %{version: ver} = pkg) when not is_nil(ver), do: pkg
  defp prefer_versioned(existing, _pkg), do: existing

  # --- Matching & Version Range Evaluation ---

  defp match_cves(cves, packages) do
    Enum.reduce(cves, {[], []}, fn post, {matches_acc, cleared_acc} ->
      {matched_details, cleared_entries} = evaluate_post(post, packages)

      next_matches =
        if matched_details == [],
          do: matches_acc,
          else: [build_cve_match(post, matched_details) | matches_acc]

      {next_matches, cleared_entries ++ cleared_acc}
    end)
  end

  defp evaluate_post(post, packages) do
    facts = post.cve_facts
    structured = (facts && facts.packages) || []

    if structured != [] do
      evaluate_structured_post(post, structured, packages)
    else
      evaluate_unstructured_post(post, packages)
    end
  end

  defp evaluate_structured_post(post, structured, packages) do
    Enum.reduce(packages, {[], []}, fn pkg, acc ->
      evaluate_structured_pkg(post, structured, pkg, acc)
    end)
  end

  defp evaluate_structured_pkg(post, structured, pkg, {matched_acc, cleared_acc}) do
    case find_matching_structured(structured, pkg) do
      [] ->
        {matched_acc, cleared_acc}

      matching_sps ->
        classify_structured_pkg(post, pkg, matching_sps, {matched_acc, cleared_acc})
    end
  end

  defp classify_structured_pkg(post, pkg, matching_sps, {matched_acc, cleared_acc}) do
    fixed_all = matching_sps |> Enum.flat_map(&List.wrap(&1["fixed"])) |> Enum.uniq()
    eco = pkg.ecosystem || List.first(matching_sps)["ecosystem"]
    outcomes = Enum.map(matching_sps, &evaluate_package_version(pkg.version, &1))

    cond do
      :vulnerable in outcomes ->
        detail = build_match_detail(pkg, eco, fixed_all, :version_range)
        {[detail | matched_acc], cleared_acc}

      Enum.all?(outcomes, &(&1 == :patched)) ->
        cleared = %{
          cve_id: post.cve_now_id,
          package: pkg.name,
          ecosystem: eco,
          installed_version: pkg.version,
          fixed_versions: fixed_all,
          reason: "patched_version"
        }

        {matched_acc, [cleared | cleared_acc]}

      true ->
        basis = if pkg.version, do: :name_no_ranges, else: :unversioned_name
        detail = build_match_detail(pkg, eco, fixed_all, basis)
        {[detail | matched_acc], cleared_acc}
    end
  end

  defp build_match_detail(pkg, eco, fixed_all, basis) do
    %{
      name: pkg.name,
      ecosystem: eco,
      installed_version: pkg.version,
      fixed_versions: fixed_all,
      match_basis: basis
    }
  end

  defp evaluate_unstructured_post(post, packages) do
    facts = post.cve_facts

    haystack =
      [post.title, facts && facts.product, post.body_markdown]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")
      |> String.downcase()

    matched =
      for pkg <- packages,
          byte_size(pkg.name) >= 3,
          token_match?(haystack, pkg.name) do
        %{
          name: pkg.name,
          ecosystem: pkg.ecosystem,
          installed_version: pkg.version,
          fixed_versions: [],
          match_basis: :text_fallback
        }
      end

    {matched, []}
  end

  defp find_matching_structured(structured, %{ecosystem: eco, name: name}) do
    Enum.filter(structured, fn sp ->
      pkg_name = String.downcase(sp["name"] || "")
      pkg_eco = String.downcase(sp["ecosystem"] || "")

      pkg_name == name and
        (is_nil(eco) or eco == "" or pkg_eco in ["", "product"] or pkg_eco == eco)
    end)
  end

  defp version_in_range?(ver, range) do
    introduced_ok?(ver, range["introduced"]) and
      before_fixed?(ver, range["fixed"]) and
      within_last_affected?(ver, range["last_affected"])
  end

  defp introduced_ok?(_ver, bound) when bound in [nil, "", "0"], do: true
  defp introduced_ok?(ver, bound), do: compare_versions(ver, bound) in [:eq, :gt]

  defp before_fixed?(_ver, bound) when bound in [nil, ""], do: true
  defp before_fixed?(ver, bound), do: compare_versions(ver, bound) == :lt

  defp within_last_affected?(_ver, bound) when bound in [nil, ""], do: true
  defp within_last_affected?(ver, bound), do: compare_versions(ver, bound) in [:lt, :eq]

  defp evaluate_against_fixed_list(installed, fixed_versions) do
    {inst_nums, _} = parse_version_tuple(installed)
    inst_major = List.first(inst_nums)

    same_major =
      Enum.filter(fixed_versions, fn fv ->
        {f_nums, _} = parse_version_tuple(fv)
        List.first(f_nums) == inst_major
      end)

    candidates = if same_major != [], do: same_major, else: fixed_versions

    if Enum.any?(candidates, &(compare_versions(installed, &1) in [:eq, :gt])) do
      :patched
    else
      :vulnerable
    end
  end

  defp parse_version_tuple(raw) do
    trimmed = raw |> String.trim() |> String.replace(~r/\Av/i, "")
    without_build = trimmed |> String.split("+", parts: 2) |> hd()

    {core, pre} =
      case String.split(without_build, "-", parts: 2) do
        [c, p] -> {c, p}
        [c] -> {c, nil}
      end

    nums =
      core
      |> String.split(".")
      |> Enum.map(fn part ->
        case Integer.parse(part) do
          {n, _} -> n
          :error -> 0
        end
      end)

    {nums, pre}
  end

  defp compare_numeric_lists([], []), do: :eq
  defp compare_numeric_lists([a | ta], []), do: compare_numeric_lists([a | ta], [0])
  defp compare_numeric_lists([], [b | tb]), do: compare_numeric_lists([0], [b | tb])
  defp compare_numeric_lists([a | _], [b | _]) when a < b, do: :lt
  defp compare_numeric_lists([a | _], [b | _]) when a > b, do: :gt
  defp compare_numeric_lists([a | ta], [a | tb]), do: compare_numeric_lists(ta, tb)

  defp compare_prerelease(nil, nil), do: :eq
  defp compare_prerelease(nil, _pre), do: :gt
  defp compare_prerelease(_pre, nil), do: :lt

  defp compare_prerelease(a, b) do
    cond do
      a < b -> :lt
      a > b -> :gt
      true -> :eq
    end
  end

  defp build_cve_match(post, matched_details) do
    facts = post.cve_facts || %{}

    %{
      kind: :cve,
      id: post.cve_now_id,
      title: post.title,
      product: Map.get(facts, :product),
      severity: Map.get(facts, :severity),
      score: Map.get(facts, :score),
      exploited: Map.get(facts, :exploited, false),
      fix_available: Map.get(facts, :fix_available, false),
      ecosystems: Map.get(facts, :ecosystems, []),
      kev_due_date: Map.get(facts, :kev_due_date),
      epss_score: Map.get(facts, :epss_score),
      cwe: Map.get(facts, :cwe, []),
      ssvc: Map.get(facts, :ssvc),
      poc_signals: Map.get(facts, :poc_signals, []),
      matched_packages: matched_details |> Enum.map(& &1.name) |> Enum.uniq(),
      matched_details: matched_details,
      reply_count: post.reply_count || 0,
      patchbay_path: PostAddress.path(post),
      cve_now_url: "https://cve.now/#{post.cve_now_id}",
      modified_at: post.cve_now_modified_at
    }
  end

  defp match_briefings(briefings, packages) do
    Enum.flat_map(briefings, fn incident ->
      haystack = String.downcase("#{incident.title} #{incident.summary} #{incident.tag}")

      matched =
        for pkg <- packages,
            byte_size(pkg.name) >= 3,
            token_match?(haystack, pkg.name),
            do: pkg.name

      case Enum.uniq(matched) do
        [] -> []
        list -> [build_briefing_match(incident, list)]
      end
    end)
  end

  defp build_briefing_match(incident, matched) do
    %{
      kind: :briefing,
      id: incident.name,
      title: incident.title,
      product: incident.post_site,
      severity: :critical,
      score: nil,
      exploited: incident.status == :active,
      fix_available: true,
      ecosystems: [],
      kev_due_date: nil,
      epss_score: nil,
      cwe: [],
      ssvc: nil,
      poc_signals: [],
      matched_packages: matched,
      matched_details:
        Enum.map(matched, fn name ->
          %{
            name: name,
            ecosystem: nil,
            installed_version: nil,
            fixed_versions: [],
            match_basis: :briefing_keyword
          }
        end),
      reply_count: 0,
      patchbay_path: "/patchbay/incidents/#{incident.name}",
      cve_now_url: nil,
      modified_at: nil
    }
  end

  defp load_cves do
    case Forum.list_cve_now_posts(page: [limit: @max_cves_scanned], load: [:reply_count]) do
      {:ok, %{results: posts}} -> posts
      _ -> []
    end
  end

  defp token_match?(haystack, token) do
    escaped = Regex.escape(token)
    Regex.match?(~r/(?:^|[^a-z0-9_-])#{escaped}(?:$|[^a-z0-9_-])/i, haystack)
  end
end
