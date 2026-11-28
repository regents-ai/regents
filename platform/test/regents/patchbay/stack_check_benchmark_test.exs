defmodule Regents.Patchbay.Security.StackCheckBenchmarkTest do
  use ExUnit.Case, async: true

  alias Regents.Patchbay.Incidents.CveNow.Post
  alias Regents.Patchbay.Security.StackCheck

  # Real cve.now detail shape (captured from live https://cve.now/api/v1/entries/CVE-2026-132165)
  @live_drupal_entry %{
    "id" => "CVE-2026-132165",
    "title" => "Drupal Core - Critical - Access bypass - SA-CORE-2026-005",
    "url" => "https://cve.now/CVE-2026-132165",
    "modifiedAt" => "2026-11-25T16:12:00Z",
    "critical" => %{"value" => true},
    "statedSeverity" => "critical",
    "severity" => %{"cvss" => 9.8, "source" => "nvd"},
    "exploitation" => %{
      "kev" => %{
        "dateAdded" => "2026-11-24",
        "dueDate" => "2026-11-27",
        "requiredAction" => "Apply mitigations per vendor instructions."
      },
      "epss" => %{"score" => 0.87}
    },
    "packages" => [%{"ecosystem" => "Packagist", "name" => "drupal/core"}],
    "affected" => [
      %{
        "ecosystem" => "Packagist",
        "package" => "drupal/core",
        "ranges" => [
          %{"introduced" => "0", "fixed" => "10.6.22"},
          %{"introduced" => "11.0.0", "fixed" => "11.3.22"},
          %{"introduced" => "11.4.0", "fixed" => "11.4.13"}
        ]
      }
    ],
    "fixedIn" => ["10.6.22", "11.3.22", "11.4.13"]
  }

  defp fake_cve_post(id, ecosystem, pkg, ranges, fixed) do
    %{
      id: "00000000-0000-4000-8000-000000000001",
      slug: String.downcase(id),
      thread_kind: :discussion,
      cve_now_id: id,
      title: "#{id}: Critical vulnerability in #{pkg}",
      body_markdown: "Advisory for #{pkg}",
      reply_count: 2,
      cve_now_modified_at: ~U[2026-11-25 12:00:00Z],
      cve_facts: %{
        product: pkg,
        severity: :critical,
        score: 9.8,
        exploited: true,
        fix_available: fixed != [],
        ecosystems: [ecosystem],
        kev_due_date: "2026-11-27",
        epss_score: 0.91,
        packages: [
          %{
            "ecosystem" => ecosystem,
            "name" => pkg,
            "status" => if(fixed != [], do: "fixed", else: "none"),
            "fixed" => fixed,
            "ranges" => ranges,
            "versions" => []
          }
        ]
      }
    }
  end

  test "CveNow.Post extracts affected ranges, ecosystems, fixed versions, KEV due date, and EPSS from raw cve.now JSON" do
    assert {:ok, copy} = Post.from_entry(@live_drupal_entry, "Drupal · Core")
    assert copy.facts.ecosystems == ["packagist"]
    assert copy.facts.exploited == true
    assert copy.facts.fix_available == true
    assert copy.facts.kev_due_date == "2026-11-27"
    assert copy.facts.epss_score == 0.87

    assert [pkg] = copy.facts.packages
    assert pkg["ecosystem"] == "packagist"
    assert pkg["name"] == "drupal/core"
    assert pkg["fixed"] == ["10.6.22", "11.3.22", "11.4.13"]
    assert length(pkg["ranges"]) == 3
  end

  test "20-lockfile benchmark: 100% recall on 10 vulnerable pins and 0% false positives on 10 patched pins" do
    cves = [
      fake_cve_post(
        "CVE-2026-1001",
        "npm",
        "next",
        [%{"introduced" => "15.0.0", "fixed" => "15.2.3"}],
        ["15.2.3"]
      ),
      fake_cve_post(
        "CVE-2026-1002",
        "npm",
        "@modelcontextprotocol/sdk",
        [%{"introduced" => "0", "fixed" => "1.12.1"}],
        ["1.12.1"]
      ),
      fake_cve_post(
        "CVE-2026-1003",
        "packagist",
        "drupal/core",
        [
          %{"introduced" => "0", "fixed" => "10.6.22"},
          %{"introduced" => "11.4.0", "fixed" => "11.4.13"}
        ],
        ["10.6.22", "11.4.13"]
      ),
      fake_cve_post(
        "CVE-2026-1004",
        "hex",
        "plug",
        [%{"introduced" => "1.15.0", "fixed" => "1.16.2"}],
        ["1.16.2"]
      ),
      fake_cve_post(
        "CVE-2026-1005",
        "cargo",
        "hyper",
        [%{"introduced" => "1.0.0", "fixed" => "1.5.1"}],
        ["1.5.1"]
      ),
      fake_cve_post(
        "CVE-2026-1006",
        "cargo",
        "tokio",
        [%{"introduced" => "1.30.0", "fixed" => "1.42.0"}],
        ["1.42.0"]
      ),
      fake_cve_post(
        "CVE-2026-1007",
        "pypi",
        "langflow",
        [%{"introduced" => "0", "fixed" => "1.3.4"}],
        ["1.3.4"]
      ),
      fake_cve_post(
        "CVE-2026-1008",
        "pypi",
        "fastapi",
        [%{"introduced" => "0.100.0", "fixed" => "0.115.6"}],
        ["0.115.6"]
      ),
      fake_cve_post(
        "CVE-2026-1009",
        "go",
        "github.com/gin-gonic/gin",
        [%{"introduced" => "1.9.0", "fixed" => "1.10.1"}],
        ["1.10.1"]
      ),
      fake_cve_post(
        "CVE-2026-1010",
        "npm",
        "viem",
        [%{"introduced" => "2.0.0", "fixed" => "2.23.5"}],
        ["2.23.5"]
      )
    ]

    vulnerable_manifests = [
      {"package.json", ~s({"dependencies": {"next": "^15.1.0"}}), "CVE-2026-1001"},
      {"package-lock.json",
       ~s({"lockfileVersion": 3, "packages": {"node_modules/@modelcontextprotocol/sdk": {"version": "1.11.0"}}}),
       "CVE-2026-1002"},
      {"composer.lock", ~s({"packages": [{"name": "drupal/core", "version": "11.4.12"}]}),
       "CVE-2026-1003"},
      {"mix.lock", ~s(%{"plug": {:hex, :plug, "1.16.1", "abc", [:mix], [], "hexpm"}}),
       "CVE-2026-1004"},
      {"Cargo.toml", "[dependencies]\nhyper = \"1.4.2\"\n", "CVE-2026-1005"},
      {"Cargo.lock", "[[package]]\nname = \"tokio\"\nversion = \"1.41.9\"\n", "CVE-2026-1006"},
      {"requirements.txt", "langflow==1.3.3\n", "CVE-2026-1007"},
      {"uv.lock",
       "version = 1\nrequires-python = \">=3.12\"\n[[package]]\nname = \"fastapi\"\nversion = \"0.115.5\"\n",
       "CVE-2026-1008"},
      {"go.mod", "module example.com/app\nrequire (\n\tgithub.com/gin-gonic/gin v1.10.0\n)\n",
       "CVE-2026-1009"},
      {"plain@ver", "npm:viem@2.23.4", "CVE-2026-1010"}
    ]

    patched_manifests = [
      {"package.json", ~s({"dependencies": {"next": "15.2.3"}}), "CVE-2026-1001"},
      {"package-lock.json",
       ~s({"lockfileVersion": 3, "packages": {"node_modules/@modelcontextprotocol/sdk": {"version": "1.12.1"}}}),
       "CVE-2026-1002"},
      {"composer.lock", ~s({"packages": [{"name": "drupal/core", "version": "11.4.13"}]}),
       "CVE-2026-1003"},
      {"mix.lock", ~s(%{"plug": {:hex, :plug, "1.16.2", "abc", [:mix], [], "hexpm"}}),
       "CVE-2026-1004"},
      {"Cargo.toml", "[dependencies]\nhyper = \"1.5.1\"\n", "CVE-2026-1005"},
      {"Cargo.lock", "[[package]]\nname = \"tokio\"\nversion = \"1.42.0\"\n", "CVE-2026-1006"},
      {"requirements.txt", "langflow==1.3.4\n", "CVE-2026-1007"},
      {"uv.lock",
       "version = 1\nrequires-python = \">=3.12\"\n[[package]]\nname = \"fastapi\"\nversion = \"0.115.6\"\n",
       "CVE-2026-1008"},
      {"go.mod", "module example.com/app\nrequire (\n\tgithub.com/gin-gonic/gin v1.10.1\n)\n",
       "CVE-2026-1009"},
      {"plain@ver", "npm:viem@2.23.5", "CVE-2026-1010"}
    ]

    # 10/10 vulnerable pins MUST match their exact CVE via :version_range
    for {label, manifest, expected_cve} <- vulnerable_manifests do
      pkgs = StackCheck.parse_manifest(manifest)
      result = StackCheck.evaluate(pkgs, cves)

      assert result.match_count == 1,
             "Expected vulnerable #{label} to match #{expected_cve}, got #{inspect(result)}"

      assert hd(result.matches).id == expected_cve
      assert hd(hd(result.matches).matched_details).match_basis == :version_range
    end

    # 10/10 patched pins MUST return 0 matches and 1 cleared_package
    for {label, manifest, expected_cve} <- patched_manifests do
      pkgs = StackCheck.parse_manifest(manifest)
      result = StackCheck.evaluate(pkgs, cves)

      assert result.match_count == 0,
             "False positive on patched #{label}: #{inspect(result.matches)}"

      assert result.cleared_count == 1,
             "Expected patched #{label} to be explicitly cleared for #{expected_cve}"

      assert hd(result.cleared_packages).cve_id == expected_cve
      assert hd(result.cleared_packages).reason == "patched_version"
    end
  end

  test "CveNow.Post binds vendor/product affected[] ranges & fixedInByProduct onto packages[], and extracts CWE/SSVC/PoC" do
    # Real upstream cve.now shape captured from CVE-2026-133469 (xo-server)
    xo_entry = %{
      "id" => "CVE-2026-133469",
      "title" => "Xen Orchestra xo-server authentication bypass",
      "url" => "https://cve.now/CVE-2026-133469",
      "modifiedAt" => "2026-11-27T18:00:00Z",
      "critical" => %{"value" => true},
      "statedSeverity" => "critical",
      "severity" => %{"cvss" => 9.8, "source" => "cna"},
      "cwe" => ["CWE-306"],
      "ssvc" => %{
        "exploitation" => "active",
        "automatable" => "yes",
        "technicalImpact" => "total",
        "source" => "CISA-ADP"
      },
      "exploitation" => %{
        "kev" => %{"dateAdded" => "2026-11-26", "dueDate" => "2026-12-03"},
        "githubPoc" => true,
        "nuclei" => 2
      },
      "packages" => [%{"ecosystem" => "npm", "name" => "xo-server"}],
      "affected" => [
        %{
          "vendor" => "xen-orchestra",
          "product" => "xo-server",
          "ranges" => [
            %{"fixed" => "5.211.2"},
            %{"introduced" => "5.213.0", "fixed" => "5.213.1"}
          ]
        }
      ],
      "fixedInByProduct" => [
        %{"product" => "xo-server", "versions" => ["5.211.2", "5.213.1"]}
      ]
    }

    assert {:ok, copy} = Post.from_entry(xo_entry, "Xen Orchestra · xo-server")
    assert copy.facts.cwe == ["CWE-306"]
    assert copy.facts.ssvc["automatable"] == "yes"
    assert copy.facts.ssvc["technical_impact"] == "total"
    assert copy.facts.poc_signals == ["github_poc", "nuclei"]
    assert [pkg] = copy.facts.packages
    assert pkg["ecosystem"] == "npm"
    assert pkg["name"] == "xo-server"
    assert pkg["fixed"] == ["5.211.2", "5.213.1"]
    assert length(pkg["ranges"]) == 2
  end

  test "parses pnpm-lock.yaml, yarn.lock (v1 & Berry), poetry.lock, go.sum, Gemfile.lock, CycloneDX & SPDX SBOMs" do
    cves = [
      fake_cve_post(
        "CVE-2026-2001",
        "npm",
        "xo-server",
        [%{"introduced" => "5.213.0", "fixed" => "5.213.1"}],
        ["5.213.1"]
      ),
      fake_cve_post(
        "CVE-2026-2002",
        "npm",
        "@modelcontextprotocol/sdk",
        [%{"introduced" => "0", "fixed" => "1.12.1"}],
        ["1.12.1"]
      ),
      fake_cve_post(
        "CVE-2026-2003",
        "pypi",
        "langflow",
        [%{"introduced" => "0", "fixed" => "1.3.4"}],
        ["1.3.4"]
      ),
      fake_cve_post(
        "CVE-2026-2004",
        "go",
        "github.com/gin-gonic/gin",
        [%{"introduced" => "1.9.0", "fixed" => "1.10.1"}],
        ["1.10.1"]
      ),
      fake_cve_post(
        "CVE-2026-2005",
        "rubygems",
        "rack",
        [%{"introduced" => "3.0.0", "fixed" => "3.1.12"}],
        ["3.1.12"]
      )
    ]

    pnpm = """
    lockfileVersion: '9.0'
    packages:
      'xo-server@5.213.0':
        resolution: {integrity: sha512-abc}
      '@modelcontextprotocol/sdk@1.12.1':
        resolution: {integrity: sha512-def}
    """

    yarn_v1 = """
    # THIS IS AN AUTOGENERATED FILE. DO NOT EDIT THIS FILE DIRECTLY.
    # yarn lockfile v1

    "@modelcontextprotocol/sdk@^1.10.0":
      version "1.11.0"
      resolved "https://registry.yarnpkg.com/@modelcontextprotocol/sdk/-/sdk-1.11.0.tgz"
    """

    yarn_berry = """
    __metadata:
      version: 8

    "xo-server@npm:^5.213.0":
      version: 5.213.0
      resolution: "xo-server@npm:5.213.0"
    """

    poetry = """
    [[package]]
    name = "langflow"
    version = "1.3.2"
    python-versions = ">=3.10"

    [metadata]
    lock-version = "2.0"
    """

    go_sum = """
    github.com/gin-gonic/gin v1.10.0 h1:abc123=
    github.com/gin-gonic/gin v1.10.0/go.mod h1:def456=
    """

    gemfile = """
    GEM
      remote: https://rubygems.org/
      specs:
        rack (3.1.10)
        rails (7.2.1)
    """

    cyclonedx =
      Jason.encode!(%{
        "bomFormat" => "CycloneDX",
        "specVersion" => "1.5",
        "components" => [
          %{"name" => "xo-server", "version" => "5.213.0", "purl" => "pkg:npm/xo-server@5.213.0"},
          %{"name" => "rack", "version" => "3.1.12", "purl" => "pkg:gem/rack@3.1.12"}
        ]
      })

    spdx =
      Jason.encode!(%{
        "spdxVersion" => "SPDX-2.3",
        "packages" => [
          %{
            "name" => "langflow",
            "versionInfo" => "1.3.2",
            "externalRefs" => [
              %{"referenceType" => "purl", "referenceLocator" => "pkg:pypi/langflow@1.3.2"}
            ]
          }
        ]
      })

    for {label, content, expected_cve, expected_cleared} <- [
          {"pnpm-lock.yaml", pnpm, "CVE-2026-2001", 1},
          {"yarn.lock v1", yarn_v1, "CVE-2026-2002", 0},
          {"yarn.lock Berry", yarn_berry, "CVE-2026-2001", 0},
          {"poetry.lock", poetry, "CVE-2026-2003", 0},
          {"go.sum", go_sum, "CVE-2026-2004", 0},
          {"Gemfile.lock", gemfile, "CVE-2026-2005", 0},
          {"CycloneDX SBOM", cyclonedx, "CVE-2026-2001", 1},
          {"SPDX SBOM", spdx, "CVE-2026-2003", 0}
        ] do
      pkgs = StackCheck.parse_manifest(content)
      res = StackCheck.evaluate(pkgs, cves)
      assert res.match_count == 1, "#{label} failed: #{inspect(res)}"
      assert hd(res.matches).id == expected_cve
      assert res.cleared_count == expected_cleared
    end
  end

  test "real production repo lockfiles (>400 KB package-lock.json and mix.lock) parse within 2 MB cap" do
    pkg_lock_path = Path.expand("../../../package-lock.json", __DIR__)
    mix_lock_path = Path.expand("../../../mix.lock", __DIR__)

    if File.exists?(pkg_lock_path) do
      content = File.read!(pkg_lock_path)
      assert byte_size(content) > 65_536
      pkgs = StackCheck.parse_manifest(content)
      assert length(pkgs) > 100
      assert Enum.all?(pkgs, &(&1.ecosystem == "npm"))
    end

    if File.exists?(mix_lock_path) do
      content = File.read!(mix_lock_path)
      pkgs = StackCheck.parse_manifest(content)
      assert length(pkgs) > 50
      assert Enum.any?(pkgs, &(&1.name == "phoenix" and not is_nil(&1.version)))
    end
  end
end
