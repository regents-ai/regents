defmodule Regents.Patchbay.Security.StackCheck do
  @moduledoc """
  Matches a project's dependency manifest (`package.json`, `mix.lock`,
  `requirements.txt`, `Cargo.toml`, `go.mod`, or comma/newline package list)
  against Patchbay's live mirrored `cve.now` active criticals and curated
  security briefings, returning each matched CVE together with its Patchbay
  mitigation discussion thread.
  """

  alias Regents.Patchbay.Forum
  alias Regents.Patchbay.Forum.PostAddress
  alias Regents.Patchbay.Incidents

  @max_input_bytes 64 * 1024
  @max_packages 200
  @max_cves_scanned 250

  @doc """
  Parse raw manifest text or a structured package list and match against
  Patchbay's active critical CVE mirror and incident briefings.
  """
  @spec check(String.t() | [map()]) :: {:ok, map()} | {:error, String.t()}
  def check(input) when is_binary(input) do
    if byte_size(input) > @max_input_bytes do
      {:error, "Manifest text exceeds 64 KB limit."}
    else
      packages = parse_manifest(input)

      if packages == [] do
        {:error,
         "No package names detected. Paste package.json, mix.lock, requirements.txt, Cargo.toml, go.mod, or a comma/line-separated list of packages."}
      else
        match_packages(packages)
      end
    end
  end

  def check(packages) when is_list(packages) do
    normalized =
      packages
      |> Enum.flat_map(&normalize_package_entry/1)
      |> Enum.uniq_by(&{&1.ecosystem, &1.name})
      |> Enum.take(@max_packages)

    if normalized == [] do
      {:error, "Provide at least one package name to check."}
    else
      match_packages(normalized)
    end
  end

  def check(_other), do: {:error, "Provide manifest text or a list of packages."}

  @doc "Extract normalized `{ecosystem, name}` entries from common manifest formats."
  @spec parse_manifest(String.t()) :: [%{ecosystem: String.t() | nil, name: String.t()}]
  def parse_manifest(text) when is_binary(text) do
    trimmed = String.trim(text)

    cond do
      trimmed == "" ->
        []

      String.starts_with?(trimmed, "{") ->
        parse_package_json(trimmed)

      String.contains?(trimmed, "{:hex,") ->
        parse_mix_lock(trimmed)

      String.contains?(trimmed, "[dependencies]") or String.contains?(trimmed, "[[package]]") ->
        parse_cargo(trimmed)

      String.contains?(trimmed, "module ") and String.contains?(trimmed, "require") ->
        parse_go_mod(trimmed)

      true ->
        parse_plain_or_requirements(trimmed)
    end
    |> Enum.uniq_by(&{&1.ecosystem, &1.name})
    |> Enum.take(@max_packages)
  end

  defp parse_package_json(text) do
    case Jason.decode(text) do
      {:ok, %{} = map} ->
        keys =
          Map.keys(map["dependencies"] || %{}) ++
            Map.keys(map["devDependencies"] || %{}) ++
            Map.keys(map["peerDependencies"] || %{})

        Enum.map(keys, &%{ecosystem: "npm", name: String.downcase(&1)})

      _ ->
        parse_plain_or_requirements(text)
    end
  end

  defp parse_mix_lock(text) do
    Regex.scan(~r/"([a-z0-9_]+)":\s*\{:hex,/i, text)
    |> Enum.map(fn [_, name] -> %{ecosystem: "hex", name: String.downcase(name)} end)
  end

  defp parse_cargo(text) do
    from_toml =
      Regex.scan(~r/^\s*([a-zA-Z0-9_-]+)\s*=\s*(?:"|\{)/m, text)
      |> Enum.map(fn [_, name] -> String.downcase(name) end)
      |> Enum.reject(&(&1 in ~w(name version edition authors license description repository)))

    from_lock =
      Regex.scan(~r/^\s*name\s*=\s*"([^"]+)"/m, text)
      |> Enum.map(fn [_, name] -> String.downcase(name) end)

    (from_toml ++ from_lock)
    |> Enum.uniq()
    |> Enum.map(&%{ecosystem: "cargo", name: &1})
  end

  defp parse_go_mod(text) do
    Regex.scan(~r/^\s*([a-z0-9.-]+\/[a-z0-9._\/-]+)\s+v[0-9]/im, text)
    |> Enum.map(fn [_, mod] -> %{ecosystem: "go", name: String.downcase(mod)} end)
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
      String.contains?(cleaned, ":") -> parse_prefixed_pkg(cleaned)
      true -> parse_bare_pkg(cleaned)
    end
  end

  defp parse_prefixed_pkg(cleaned) do
    case String.split(cleaned, ":", parts: 2) do
      [eco, name] -> [%{ecosystem: String.downcase(String.trim(eco)), name: clean_pkg_name(name)}]
      _ -> []
    end
  end

  defp parse_bare_pkg(cleaned) do
    name = clean_pkg_name(cleaned)
    if name == "", do: [], else: [%{ecosystem: nil, name: name}]
  end

  defp clean_pkg_name(raw) do
    raw
    |> String.trim()
    |> String.split(~r/[=<>!~;@\[\s]/, parts: 2)
    |> hd()
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_package_entry(%{"name" => name} = entry) when is_binary(name) do
    cleaned = clean_pkg_name(name)
    eco = if is_binary(entry["ecosystem"]), do: String.downcase(String.trim(entry["ecosystem"]))
    if cleaned == "", do: [], else: [%{ecosystem: eco, name: cleaned}]
  end

  defp normalize_package_entry(%{name: name} = entry) when is_binary(name) do
    cleaned = clean_pkg_name(name)
    eco = if is_binary(entry[:ecosystem]), do: String.downcase(String.trim(entry[:ecosystem]))
    if cleaned == "", do: [], else: [%{ecosystem: eco, name: cleaned}]
  end

  defp normalize_package_entry(name) when is_binary(name) do
    parse_plain_or_requirements(name)
  end

  defp normalize_package_entry(_other), do: []

  defp match_packages(packages) do
    cves = load_cves()

    matches =
      (match_cves(cves, packages) ++ match_briefings(Incidents.all(), packages))
      |> Enum.sort_by(&{not &1.exploited, -(&1.score || 0.0)})

    {:ok,
     %{
       checked_packages: packages,
       package_count: length(packages),
       cves_scanned: length(cves),
       match_count: length(matches),
       kev_match_count: Enum.count(matches, & &1.exploited),
       unfixed_match_count: Enum.count(matches, &(not &1.fix_available)),
       matches: matches
     }}
  end

  defp match_cves(cves, packages) do
    Enum.flat_map(cves, fn post ->
      case matching_packages_for_post(post, packages) do
        [] -> []
        matched -> [build_cve_match(post, matched)]
      end
    end)
  end

  defp build_cve_match(post, matched) do
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
      matched_packages: matched,
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
      matched_packages: matched,
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

  defp matching_packages_for_post(post, packages) do
    facts = post.cve_facts
    structured = (facts && facts.packages) || []

    haystack =
      [post.title, facts && facts.product, post.body_markdown]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")
      |> String.downcase()

    packages
    |> Enum.filter(fn pkg ->
      structured_match?(structured, pkg) or
        (byte_size(pkg.name) >= 3 and token_match?(haystack, pkg.name))
    end)
    |> Enum.map(& &1.name)
    |> Enum.uniq()
  end

  defp structured_match?(structured, %{ecosystem: eco, name: name}) do
    Enum.any?(structured, fn sp ->
      pkg_name = String.downcase(sp["name"] || "")
      pkg_eco = String.downcase(sp["ecosystem"] || "")
      pkg_name == name and (is_nil(eco) or eco == "" or pkg_eco == eco)
    end)
  end

  defp token_match?(haystack, token) do
    escaped = Regex.escape(token)
    Regex.match?(~r/(?:^|[^a-z0-9_-])#{escaped}(?:$|[^a-z0-9_-])/i, haystack)
  end
end
