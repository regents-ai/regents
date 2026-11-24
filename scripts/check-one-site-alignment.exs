#!/usr/bin/env elixir
# Read-only cross-product alignment audit against docs/one-site-standard.md.
# Run from the repository root: `make check-alignment` (or `elixir scripts/check-one-site-alignment.exs`).

root = Path.expand("..", __DIR__)
platform = Path.join(root, "platform")
products = ~w(patchbay techtree autolaunch keyfleet)

read! = fn rel -> File.read!(Path.join(root, rel)) end
exists? = fn rel -> File.exists?(Path.join(root, rel)) end

router = read!.("platform/lib/regents_web/router.ex")
config = read!.("platform/config/config.exs")
products_ex = read!.("platform/lib/regents/products.ex")
site_tools_ex = read!.("platform/lib/regents/site_tools.ex")
product_webmcp = read!.("platform/assets/js/product_webmcp.ts")

grep_files = fn glob, pattern ->
  Path.wildcard(Path.join(platform, glob))
  |> Enum.filter(fn path ->
    File.regular?(path) and Regex.match?(pattern, File.read!(path))
  end)
end

check_product = fn p ->
  mod = Macro.camelize(p)

  # 1. Code
  boundaries_ok =
    exists?.("platform/lib/regents/#{p}.ex") and
      exists?.("platform/lib/regents_web/#{p}.ex") and
      String.contains?(products_ex, ~s(name: "#{p}"))

  shared_agent_plug_ok =
    length(grep_files.("lib/regents_web/#{p}/**/*.ex", ~r/RegentsWeb\.Account\.PairedAgent/)) > 0 or
      String.contains?(router, "paired_agent")

  actors_agent_ok =
    length(grep_files.("lib/{regents,regents_web}/#{p}/**/*.ex", ~r/Actors\.Agent/)) > 0

  ash_policies_ok =
    length(
      grep_files.(
        "lib/{regents,regents_web}/#{p}/**/*.ex",
        ~r/RegentAgents\.(Checks\.Paired|RequirePairing)/
      )
    ) > 0

  agent_tools_file = "platform/lib/regents_web/#{p}/agent_tools.ex"
  agent_tools_ok =
    exists?.(agent_tools_file) and
      String.contains?(config, "RegentsWeb.#{mod}.AgentTools")

  # 2. UI
  layouts_file = "platform/lib/regents_web/#{p}/layouts.ex"
  layouts_src = if exists?.(layouts_file), do: read!.(layouts_file), else: ""

  shell_frame_ok =
    (String.contains?(layouts_src, ~s(Shell.site_bar)) or
       length(grep_files.("lib/regents_web/#{p}/**/*.ex", ~r/Shell\.site_bar/)) > 0) and
      (String.contains?(layouts_src, "Regent.Structure.frame") or
         length(grep_files.("lib/regents_web/#{p}/**/*.ex", ~r/Regent\.Structure\.frame/)) > 0)

  on_mount_page_ok =
    String.contains?(layouts_src, "def on_mount(:page") or
      String.contains?(router, "{RegentsWeb.Layouts, :page}") or
      String.contains?(router, "{RegentsWeb.#{mod}.Layouts, :page}")

  css_files = Path.wildcard(Path.join(platform, "assets/css/#{p}/**/*.css"))
  expected_scope = "@scope (:root[data-product=\"#{p}\"]:not([data-marketing]))"

  bad_css =
    css_files
    |> Enum.reject(&(Path.basename(&1) == "index.css"))
    |> Enum.reject(fn f -> String.contains?(File.read!(f), expected_scope) end)

  css_scope_ok = css_files != [] and bad_css == []

  # 3. WebMCP & CLI
  manifest_ok = exists?.("platform/priv/#{p}/tool_manifest.json")

  capabilities_route_ok =
    String.contains?(router, ~s("/\#{product}/capabilities")) or
      String.contains?(router, ~s("/api/v1/#{p}/capabilities"))

  webmcp_wired_ok =
    String.contains?(product_webmcp, "#{p}: [") and
      String.contains?(product_webmcp, "/api/v1/${encodeURIComponent(product)}/capabilities")

  site_tools_ok = String.contains?(site_tools_ex, "priv/#{p}/tool_manifest.json")

  docs_routes_ok =
    Enum.all?(~w(skill.md llms.txt agents.md), fn doc ->
      String.contains?(router, ~s("/#{doc}")) and
        (String.contains?(router, ~s(scope "/#{p}")) or String.contains?(router, ~s(product: "#{p}")))
    end)

  # 4. Database
  schema_ok = String.contains?(products_ex, ~s(schema: "#{p}_app"))
  migrations_ok = File.dir?(Path.join(platform, "priv/#{p}/migrations"))

  identity_anchors_ok =
    length(
      grep_files.(
        "lib/regents/#{p}/**/*.ex",
        ~r/\b(human_account_id|privy_user_id|pairing_id)\b/
      )
    ) > 0

  checks = [
    {"1.Boundaries", boundaries_ok},
    {"1.Actors.Agent", actors_agent_ok},
    {"1.PairedAgent", shared_agent_plug_ok},
    {"1.AshPolicies", ash_policies_ok},
    {"1.AgentTools/MCP", agent_tools_ok},
    {"2.Shell+Frame", shell_frame_ok},
    {"2.on_mount(:page)", on_mount_page_ok},
    {"2.CSS @scope", css_scope_ok},
    {"3.tool_manifest", manifest_ok},
    {"3./capabilities", capabilities_route_ok},
    {"3.product_webmcp", webmcp_wired_ok},
    {"3.SiteTools", site_tools_ok},
    {"3.skill/llms/agents", docs_routes_ok},
    {"4.<p>_app schema", schema_ok},
    {"4.priv/<p>/migrations", migrations_ok},
    {"4.Identity anchors", identity_anchors_ok}
  ]

  {p, checks, bad_css}
end

results = Enum.map(products, check_product)

IO.puts("# One-Site Cross-Product Alignment Matrix\n")
IO.puts("| Product | Code (5) | UI (3) | WebMCP & CLI (5) | DB (3) | Gaps |")
IO.puts("| --- | --- | --- | --- | --- | --- |")

for {p, checks, bad_css} <- results do
  count = fn prefix ->
    matching = Enum.filter(checks, fn {k, _} -> String.starts_with?(k, prefix) end)
    ok = Enum.count(matching, fn {_, v} -> v end)
    "#{ok}/#{length(matching)}"
  end

  gaps =
    checks
    |> Enum.reject(fn {_, v} -> v end)
    |> Enum.map(fn {k, _} ->
      if k == "2.CSS @scope" and bad_css != [] do
        "#{k} (#{length(bad_css)} files)"
      else
        k
      end
    end)

  gap_str = if gaps == [], do: "none", else: Enum.join(gaps, ", ")
  IO.puts("| `#{p}` | #{count.("1.")} | #{count.("2.")} | #{count.("3.")} | #{count.("4.")} | #{gap_str} |")
end
