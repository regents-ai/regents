defmodule Regents.Patchbay.Incidents.CveNow.Post do
  @moduledoc """
  The post a cve.now record is copied into, made only from what the record
  says: a title of its id and its own title, a tag of its id, and a Markdown
  body. The body opens with cve.now's summary, or the CVE record's own
  description when there is no summary, then gives the severity, what is
  affected, the fix, the record's references, and a line crediting the
  record on cve.now with a link to it.

  Every word of it is cve.now's, so each piece is kept to one line and its
  Markdown marks are escaped: it reads as written and adds no heading, list
  or link of its own.

  Beside the words, the facts the post's badges show (`Regents.Patchbay.Forum.CveFacts`):
  the level cve.now states, or else the CVSS band of its score; the score;
  whether CISA lists it as exploited and whether cve.now lists a fix, both
  as the body says them; and the vendor and product line cve.now's list
  shows, which the record itself does not carry.
  """

  alias Regents.Patchbay.Forum.TopicTag

  # A post's title holds at most this many characters (`Regents.Patchbay.Forum.Report`),
  # and so does its vendor and product line.
  @max_title 160
  # More references than this are counted rather than listed.
  @max_references 25
  @web_address ~r{\Ahttps?://[^\s<>]+\z}
  @stated %{
    "critical" => :critical,
    "high" => :high,
    "medium" => :medium,
    "low" => :low,
    "none" => :none
  }

  @type t :: %{
          id: String.t(),
          modified_at: DateTime.t(),
          title: String.t(),
          tag: String.t(),
          body: String.t(),
          facts: %{
            severity: Regents.Patchbay.Forum.Types.CveSeverity.t() | nil,
            score: float() | nil,
            exploited: boolean(),
            fix_available: boolean(),
            product: String.t() | nil
          }
        }

  @doc """
  The post for one record as `GET /api/v1/entries/<id>` answers it, with
  `product`, the vendor and product line `GET /api/v1/entries` lists it
  under (nil when the list gives none).
  `:not_critical` when cve.now does not rate the record critical (a record
  on CISA's list of exploited vulnerabilities always is); `:malformed` when
  it lacks an id that can be a tag, a title, its address on cve.now or when
  it last changed.
  """
  @spec from_entry(term(), String.t() | nil) ::
          {:ok, t()} | {:error, :not_critical | :malformed}
  def from_entry(%{"critical" => %{"value" => false}}, _product), do: {:error, :not_critical}

  def from_entry(
        %{
          "id" => id,
          "title" => title,
          "url" => "https://cve.now/" <> _ = url,
          "modifiedAt" => modified,
          "critical" => %{"value" => true}
        } = entry,
        product
      )
      when is_binary(id) and is_binary(title) and is_binary(modified) do
    tag = String.downcase(id)

    with true <- TopicTag.valid?(tag) and line(title) != "",
         {:ok, modified_at, _offset} <- DateTime.from_iso8601(modified) do
      {:ok,
       %{
         id: id,
         modified_at: modified_at,
         title: shortened(id <> ": " <> line(title)),
         tag: tag,
         body: body(entry, url),
         facts: facts(entry, product)
       }}
    else
      _not_a_record -> {:error, :malformed}
    end
  end

  def from_entry(_entry, _product), do: {:error, :malformed}

  defp shortened(words) do
    if String.length(words) <= @max_title,
      do: words,
      else: (words |> String.slice(0, @max_title - 1) |> String.replace(~r/\s+\S*\z/u, "")) <> "…"
  end

  @agent_stack_terms ~w(
    mcp modelcontextprotocol langchain langgraph langflow openai anthropic
    claude codex cursor llama ollama vllm litellm autogen crewai
    viem ethers web3 solana privy coinbase x402 tempo stripe
    next nextjs react node express fastify vite webpack
    elixir phoenix plug bandit otp erlang
    python fastapi pydantic uvicorn starlette django flask
    openssl curl nginx envoy caddy docker kubernetes containerd
  )

  defp facts(entry, product) do
    score = score(entry)
    packages = structured_packages(entry)
    ecosystems = extract_ecosystems(packages)
    product_text = product_line(product)

    %{
      severity: stated_level(entry) || band(score),
      score: score,
      exploited: kev(entry) != [],
      fix_available:
        fixed_in(entry) != [] or Enum.any?(fix_packages(entry), &fixed?/1) or
          Enum.any?(packages, &((&1["fixed"] || []) != [])),
      product: product_text,
      ecosystems: ecosystems,
      packages: packages,
      epss_score: epss_score(entry),
      kev_due_date: kev_due_date(entry),
      exposure: exposure_value(entry),
      agent_ecosystem: agent_ecosystem?(entry, product_text, packages),
      cwe: extract_cwe(entry),
      ssvc: extract_ssvc(entry),
      poc_signals: extract_poc_signals(entry)
    }
  end

  defp epss_score(%{"exploitation" => %{"epss" => %{"score" => score}}})
       when is_number(score) and score >= 0 and score <= 1,
       do: score / 1

  defp epss_score(%{"scores" => %{"epss" => %{"score" => score}}})
       when is_number(score) and score >= 0 and score <= 1,
       do: score / 1

  defp epss_score(%{"epss" => %{"score" => score}})
       when is_number(score) and score >= 0 and score <= 1,
       do: score / 1

  defp epss_score(_entry), do: nil

  defp extract_cwe(entry) do
    entry
    |> list("cwe")
    |> Enum.filter(&(is_binary(&1) and String.trim(&1) != ""))
    |> Enum.map(&line/1)
    |> Enum.uniq()
    |> Enum.take(10)
  end

  defp extract_ssvc(%{"ssvc" => %{} = ssvc}) do
    map =
      %{}
      |> maybe_put_ssvc("exploitation", ssvc["exploitation"])
      |> maybe_put_ssvc("automatable", ssvc["automatable"])
      |> maybe_put_ssvc("technical_impact", ssvc["technicalImpact"] || ssvc["technical_impact"])
      |> maybe_put_ssvc("source", ssvc["source"])

    if map == %{}, do: nil, else: map
  end

  defp extract_ssvc(_entry), do: nil

  defp maybe_put_ssvc(acc, key, val) when is_binary(val) do
    trimmed = line(val)
    if trimmed == "", do: acc, else: Map.put(acc, key, trimmed)
  end

  defp maybe_put_ssvc(acc, _key, _val), do: acc

  defp extract_poc_signals(%{"exploitation" => %{} = exp}) do
    [
      {"githubPoc", "github_poc"},
      {"nuclei", "nuclei"},
      {"metasploit", "metasploit"},
      {"exploitDb", "exploit_db"}
    ]
    |> Enum.reduce([], fn {field, label}, acc ->
      if truthy_signal?(exp[field]), do: [label | acc], else: acc
    end)
    |> Enum.reverse()
  end

  defp extract_poc_signals(_entry), do: []

  defp truthy_signal?(true), do: true
  defp truthy_signal?(n) when is_integer(n) and n > 0, do: true
  defp truthy_signal?([_ | _]), do: true
  defp truthy_signal?(%{} = m), do: map_size(m) > 0
  defp truthy_signal?(_other), do: false

  defp kev_due_date(%{"exploitation" => %{"kev" => %{"dueDate" => due}}}) when is_binary(due),
    do: line(due)

  defp kev_due_date(_entry), do: nil

  defp exposure_value(%{"exposure" => value}) when is_binary(value),
    do: value |> line() |> String.downcase()

  defp exposure_value(_entry), do: nil

  defp structured_packages(entry) do
    top_fixed = versions(list(entry, "fixedIn"))
    from_fix_status = packages_from_fix_status(entry)
    from_list = packages_from_list(entry)
    eco_by_name = build_ecosystem_index(from_fix_status ++ from_list)
    from_affected = packages_from_affected(entry, eco_by_name)
    from_fixed_by_product = packages_from_fixed_by_product(entry, eco_by_name)

    merged =
      (from_affected ++ from_fix_status ++ from_list ++ from_fixed_by_product)
      |> Enum.reduce(%{}, &merge_structured_package/2)
      |> Map.values()
      |> Enum.sort_by(&{&1["ecosystem"], String.downcase(&1["name"])})
      |> Enum.take(30)

    case {merged, top_fixed} do
      {[single], [_ | _]} ->
        fixed = Enum.uniq((single["fixed"] || []) ++ top_fixed)
        [Map.put(single, "fixed", fixed)]

      _ ->
        merged
    end
  end

  defp build_ecosystem_index(pkgs) do
    Enum.reduce(pkgs, %{}, fn pkg, acc ->
      Map.put_new(acc, String.downcase(pkg["name"]), pkg["ecosystem"])
    end)
  end

  defp packages_from_affected(entry, eco_by_name) do
    entry
    |> list("affected")
    |> Enum.filter(&is_map/1)
    |> Enum.flat_map(&affected_item_to_package(&1, eco_by_name))
  end

  defp affected_item_to_package(item, eco_by_name) do
    ranges = normalize_ranges(item["ranges"])
    range_fixed = ranges |> Enum.map(& &1["fixed"]) |> versions() |> Enum.uniq()

    explicit_versions =
      item["versions"] |> List.wrap() |> versions() |> Enum.uniq() |> Enum.take(50)

    case resolve_affected_target(item, eco_by_name, ranges, explicit_versions) do
      {eco, name} ->
        [
          %{
            "ecosystem" => eco,
            "name" => name,
            "status" => if(range_fixed != [], do: "fixed", else: nil),
            "fixed" => range_fixed,
            "ranges" => ranges,
            "versions" => explicit_versions
          }
        ]

      nil ->
        []
    end
  end

  defp resolve_affected_target(item, eco_by_name, ranges, explicit_versions) do
    case explicit_affected_package(item) do
      {:ok, target} -> target
      :none -> product_affected_target(item["product"], eco_by_name, ranges, explicit_versions)
    end
  end

  defp explicit_affected_package(item) do
    eco = trim_non_empty(item["ecosystem"])
    pkg_name = trim_non_empty(item["package"] || item["name"])

    if eco && pkg_name, do: {:ok, {String.downcase(eco), pkg_name}}, else: :none
  end

  defp product_affected_target(raw_product, eco_by_name, ranges, explicit_versions) do
    case trim_non_empty(raw_product) do
      nil ->
        nil

      product ->
        case Map.get(eco_by_name, String.downcase(product)) do
          eco when is_binary(eco) -> {eco, product}
          nil when ranges != [] or explicit_versions != [] -> {"product", product}
          nil -> nil
        end
    end
  end

  defp trim_non_empty(val) when is_binary(val) do
    case String.trim(val) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp trim_non_empty(_other), do: nil

  defp packages_from_fixed_by_product(entry, eco_by_name) do
    for %{"product" => product, "versions" => vers} <- list(entry, "fixedInByProduct"),
        is_binary(product) and String.trim(product) != "",
        clean_vers = vers |> List.wrap() |> versions() |> Enum.uniq(),
        clean_vers != [] do
      trimmed = String.trim(product)
      eco = Map.get(eco_by_name, String.downcase(trimmed), "product")

      %{
        "ecosystem" => eco,
        "name" => trimmed,
        "status" => "fixed",
        "fixed" => clean_vers,
        "ranges" => [],
        "versions" => []
      }
    end
  end

  defp packages_from_fix_status(entry) do
    for %{"ecosystem" => eco, "package" => name} = pkg <- fix_packages(entry) do
      %{
        "ecosystem" => String.downcase(String.trim(eco)),
        "name" => String.trim(name),
        "status" => pkg["status"],
        "fixed" =>
          pkg["fixed"] |> List.wrap() |> Enum.map(&version/1) |> versions() |> Enum.uniq(),
        "ranges" => [],
        "versions" => []
      }
    end
  end

  defp packages_from_list(entry) do
    for %{"ecosystem" => eco, "name" => name}
        when is_binary(eco) and eco != "" and is_binary(name) and name != "" <-
          list(entry, "packages") do
      %{
        "ecosystem" => String.downcase(String.trim(eco)),
        "name" => String.trim(name),
        "status" => nil,
        "fixed" => [],
        "ranges" => [],
        "versions" => []
      }
    end
  end

  defp merge_structured_package(pkg, acc) do
    key = {pkg["ecosystem"], String.downcase(pkg["name"])}

    Map.update(acc, key, pkg, fn existing ->
      %{
        "ecosystem" => existing["ecosystem"],
        "name" => existing["name"],
        "status" => existing["status"] || pkg["status"],
        "fixed" => Enum.uniq((existing["fixed"] || []) ++ (pkg["fixed"] || [])),
        "ranges" => Enum.uniq((existing["ranges"] || []) ++ (pkg["ranges"] || [])),
        "versions" =>
          Enum.uniq((existing["versions"] || []) ++ (pkg["versions"] || [])) |> Enum.take(50)
      }
    end)
  end

  defp normalize_ranges(ranges) when is_list(ranges) do
    ranges
    |> Enum.filter(&is_map/1)
    |> Enum.map(fn r ->
      %{}
      |> maybe_put_range("introduced", r["introduced"])
      |> maybe_put_range("fixed", r["fixed"])
      |> maybe_put_range("last_affected", r["last_affected"] || r["lastAffected"])
    end)
    |> Enum.reject(&(&1 == %{}))
    |> Enum.uniq()
  end

  defp normalize_ranges(_other), do: []

  defp maybe_put_range(map, key, val) when is_binary(val) do
    trimmed = String.trim(val)
    if trimmed == "", do: map, else: Map.put(map, key, trimmed)
  end

  defp maybe_put_range(map, _key, _val), do: map

  defp extract_ecosystems(packages) do
    packages
    |> Enum.map(& &1["ecosystem"])
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp agent_ecosystem?(entry, product_text, packages) do
    haystack =
      [
        entry["title"],
        product_text,
        Enum.map_join(packages, " ", &"#{&1["ecosystem"]} #{&1["name"]}")
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")
      |> String.downcase()

    Enum.any?(@agent_stack_terms, &String.contains?(haystack, &1))
  end

  defp score(%{"severity" => %{"cvss" => score}})
       when is_number(score) and score >= 0 and score <= 10,
       do: score / 1

  defp score(_entry), do: nil

  defp stated_level(%{"statedSeverity" => stated}) when is_binary(stated),
    do: @stated[stated |> String.trim() |> String.downcase()]

  defp stated_level(_entry), do: nil

  # The CVSS v3 and v4 qualitative bands.
  defp band(nil), do: nil
  defp band(score) when score >= 9.0, do: :critical
  defp band(score) when score >= 7.0, do: :high
  defp band(score) when score >= 4.0, do: :medium
  defp band(score) when score > 0.0, do: :low
  defp band(_zero), do: :none

  defp fixed?(package), do: package["status"] == "fixed"

  defp product_line(product) when is_binary(product) do
    case line(product) do
      "" -> nil
      words -> shortened(words)
    end
  end

  defp product_line(_none), do: nil

  defp body(entry, url) do
    description = description(entry)

    [
      opening(description),
      section("Severity", severity(entry)),
      section("Affected", affected(entry)),
      section("Fix", fix(entry)),
      section("References", references(entry)),
      "## Source\n\n" <> credit(description, url)
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  defp description(%{"summary" => %{"text" => text}}) when is_binary(text) and text != "",
    do: {:summary, text}

  defp description(%{"originalDescription" => text}) when is_binary(text) and text != "",
    do: {:record, text}

  defp description(_entry), do: :none

  defp opening({_source, text}), do: text(text)
  defp opening(:none), do: ""

  defp credit({:summary, _text}, url),
    do:
      "Copied from #{source_link(url)}. The summary was written by a model at cve.now " <>
        "and is shared under CC BY 4.0."

  defp credit(_description, url), do: "Copied from #{source_link(url)}."

  defp source_link("https://" <> address = url), do: "[#{text(address)}](<#{url}>)"

  defp section(_heading, []), do: ""

  defp section(heading, lines),
    do: "## #{heading}\n\n" <> Enum.map_join(lines, "\n", &("- " <> &1))

  defp severity(entry), do: cvss(entry) ++ stated(entry) ++ kev(entry) ++ exposure(entry)

  defp cvss(%{"severity" => %{"cvss" => score} = severity}) when is_number(score) do
    source = if is_binary(severity["source"]), do: " (#{text(severity["source"])})", else: ""

    vector =
      if is_binary(severity["vector"]), do: ["Vector: " <> text(severity["vector"])], else: []

    ["CVSS #{score}#{source}" | vector]
  end

  defp cvss(_entry), do: []

  defp stated(%{"statedSeverity" => stated}) when is_binary(stated),
    do: ["Stated severity: " <> text(stated)]

  defp stated(_entry), do: []

  defp kev(%{"exploitation" => %{"kev" => %{"dateAdded" => added} = kev}})
       when is_binary(added) do
    due =
      if is_binary(kev["dueDate"]), do: "; CISA's due date is #{text(kev["dueDate"])}", else: ""

    action =
      if is_binary(kev["requiredAction"]),
        do: ["CISA's required action: " <> text(kev["requiredAction"])],
        else: []

    [
      "Known exploited: on CISA's Known Exploited Vulnerabilities catalog since #{text(added)}#{due}"
      | action
    ]
  end

  defp kev(_entry), do: []

  defp exposure(%{"exposure" => exposure}) when is_binary(exposure),
    do: ["Exposure: " <> text(exposure)]

  defp exposure(_entry), do: []

  defp affected(entry) do
    vendors = for %{"name" => name} when is_binary(name) <- list(entry, "vendors"), do: name
    products = for %{"name" => name} when is_binary(name) <- list(entry, "products"), do: name

    packages =
      for %{"ecosystem" => ecosystem, "name" => name}
          when is_binary(ecosystem) and is_binary(name) <- list(entry, "packages"),
          do: "#{name} (#{ecosystem})"

    named("Vendors", vendors) ++ named("Products", products) ++ named("Packages", packages)
  end

  defp named(_label, []), do: []
  defp named(label, names), do: ["#{label}: " <> text(Enum.join(names, ", "))]

  defp fix(entry) do
    case fixed_in(entry) ++ fix_status(entry) do
      [] -> ["cve.now lists no fixed version yet"]
      lines -> lines
    end
  end

  defp fixed_in(entry) do
    case versions(list(entry, "fixedIn")) do
      [] -> []
      versions -> ["Fixed in " <> text(Enum.join(versions, ", "))]
    end
  end

  defp fix_status(entry) do
    for %{"ecosystem" => ecosystem, "package" => name} = package <- fix_packages(entry) do
      text("#{name} (#{ecosystem}): #{package_fix(package)}#{latest(package["latest"])}")
    end
  end

  # The packages whose fix cve.now states: fixed, or no fixed release yet.
  defp fix_packages(%{"fixStatus" => %{"packages" => packages}}) when is_list(packages) do
    for %{"ecosystem" => ecosystem, "package" => name, "status" => status} = package
        when is_binary(ecosystem) and is_binary(name) and status in ["fixed", "none"] <- packages,
        do: package
  end

  defp fix_packages(_entry), do: []

  defp package_fix(%{"status" => "none"}), do: "no fixed release yet"

  defp package_fix(package) do
    case package["fixed"] |> List.wrap() |> Enum.map(&version/1) |> versions() do
      [] -> "fixed"
      versions -> "fixed in " <> Enum.join(versions, ", ")
    end
  end

  defp version(%{"version" => version}), do: version
  defp version(_release), do: nil

  defp latest(%{"version" => version, "affected" => false}) when is_binary(version),
    do: "; the latest release, #{version}, is not affected"

  defp latest(%{"version" => version, "affected" => true}) when is_binary(version),
    do: "; the latest release, #{version}, is still affected"

  defp latest(_latest), do: ""

  defp versions(values), do: Enum.filter(values, &(is_binary(&1) and &1 != ""))

  defp references(entry) do
    references =
      for %{"url" => url} = reference when is_binary(url) <- list(entry, "references"),
          Regex.match?(@web_address, url),
          do: reference(url, reference["role"])

    {listed, more} = Enum.split(references, @max_references)
    if more == [], do: listed, else: listed ++ ["#{length(more)} more on cve.now"]
  end

  defp reference(url, role) when is_binary(role) and role != "other",
    do: "#{link(url)} (#{text(role)})"

  defp reference(url, _role), do: link(url)

  defp link(url), do: "[#{url |> String.replace(~r{\Ahttps?://}, "") |> text()}](<#{url}>)"

  defp list(entry, key) do
    case entry[key] do
      values when is_list(values) -> values
      _none -> []
    end
  end

  # One line of cve.now's words, with every mark that Markdown reads escaped.
  defp text(words), do: words |> line() |> String.replace(~r/[\\`*_\[\]<>#|~]/, "\\\\\\0")

  defp line(words), do: words |> String.split() |> Enum.join(" ")
end
