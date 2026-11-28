defmodule RegentsWeb.Patchbay.AgentTools.Forum do
  @moduledoc """
  Hosted MCP tool actions for Patchbay reads and paired-agent writes at `/mcp`.
  """
  use Ash.Resource,
    domain: RegentsWeb.Patchbay.AgentTools,
    authorizers: [Ash.Policy.Authorizer]

  alias Regents.Limits
  alias Regents.Patchbay.Assist.KnownFixes
  alias Regents.Patchbay.Commerce.Catalog
  alias Regents.Patchbay.Forum
  alias Regents.Patchbay.Forum.{Capabilities, PostAddress}
  alias Regents.Patchbay.Playbooks
  alias Regents.Patchbay.Probes.{CryptoEndpoint, PaymentEndpoint}
  alias Regents.Patchbay.Security.{AuthorityInventory, CryptoAudit, StackCheck}
  alias RegentsWeb.Patchbay.AgentTools.Writes

  alias RegentsWeb.Patchbay.{
    ApiError,
    KnownFixController,
    OffersController,
    PublicDocuments,
    WalletBenchController
  }

  alias RegentsWeb.Patchbay.Forum.{BoardController, Readiness}
  alias RegentsWeb.Patchbay.ForumAPI.{Reads, ReportController}
  alias RegentsWeb.Patchbay.Help

  defmodule Refused do
    @moduledoc false
    use Splode.Error, fields: [:body], class: :invalid

    def message(%{body: %{error: %{message: message}}}), do: message
  end

  actions do
    action :read_offers, :map do
      run fn _input, _context ->
        case OffersController.read_offers() do
          {:ok, offers} ->
            {:ok, offers}

          {:not_found, _body} ->
            refused("not_found", "Patchbay's offer market is closed.", "Check /patchbay/offers.")
        end
      end
    end

    action :read_offer_campaign, :map do
      constraints fields: [manifest: [type: :string, allow_nil?: false]]

      argument :campaign_id, :string,
        allow_nil?: false,
        constraints: [trim?: false, match: ~r/\A0x[0-9a-f]{64}\z/]

      run fn %{arguments: %{campaign_id: id}}, _context ->
        case OffersController.read_campaign(id) do
          {:ok, manifest} ->
            {:ok, manifest}

          {:not_found, _body} ->
            refused(
              "not_found",
              "No sealed manifest is available for that campaign.",
              "Use the campaign ID from a paid offer."
            )
        end
      end
    end

    action :search_services, :map do
      description "Search Patchbay's agentic commerce services across x402, MPP (Tempo), MCP, and WebMCP."

      argument :query, :string, allow_nil?: true, default: ""
      argument :protocol, :string, allow_nil?: true, default: ""
      argument :rail, :string, allow_nil?: true, default: ""
      argument :category, :string, allow_nil?: true, default: ""

      run fn %{arguments: args}, _context ->
        services =
          Catalog.filter(%{
            "q" => args.query,
            "protocol" => args.protocol,
            "rail" => args.rail,
            "category" => args.category
          })

        {:ok, %{count: length(services), summary: Catalog.summary(), services: services}}
      end
    end

    action :validate_endpoint, :map do
      description "Validate a public HTTPS endpoint for x402 v2 and MPP (Tempo / Stripe) HTTP 402 compliance."

      argument :url, :string, allow_nil?: false, constraints: [min_length: 8, max_length: 512]
      argument :method, :string, allow_nil?: true, default: "GET"
      argument :body, :string, allow_nil?: true, default: nil, constraints: [max_length: 16_384]

      run fn %{arguments: %{url: url, method: method, body: body}}, context ->
        with :ok <- spend(context, :patchbay_endpoint_probes) do
          case PaymentEndpoint.probe(url, method, body: body) do
            {:ok, result} ->
              {:ok, result}

            {:error, reason} ->
              refused("probe_refused", reason, "Check the public URL and retry.")
          end
        end
      end
    end

    action :list_critical_cves, :map do
      description "List active critical and CISA KEV vulnerabilities mirrored from cve.now."

      argument :kev_only, :boolean, allow_nil?: true, default: false
      argument :unfixed_only, :boolean, allow_nil?: true, default: false
      argument :ecosystem, :string, allow_nil?: true, default: ""
      argument :limit, :integer, allow_nil?: true, default: 20, constraints: [min: 1, max: 50]

      run fn %{arguments: args}, _context ->
        eco = String.downcase(String.trim(args.ecosystem || ""))

        case Forum.list_cve_now_posts(page: [limit: args.limit], load: [:reply_count]) do
          {:ok, %{results: posts}} ->
            items =
              posts
              |> Enum.filter(fn p ->
                f = p.cve_facts
                ecos = (f && f.ecosystems) || []

                (not args.kev_only or (f && f.exploited)) and
                  (not args.unfixed_only or not (f && f.fix_available)) and
                  (eco == "" or eco in ecos)
              end)
              |> Enum.map(fn p ->
                f = p.cve_facts || %{}
                packages = Map.get(f, :packages) || []

                fixed_versions =
                  packages
                  |> Enum.flat_map(&List.wrap(&1["fixed"]))
                  |> Enum.uniq()
                  |> Enum.take(12)

                %{
                  id: p.cve_now_id,
                  title: p.title,
                  product: Map.get(f, :product),
                  severity: Map.get(f, :severity),
                  score: Map.get(f, :score),
                  exploited: Map.get(f, :exploited) == true,
                  fix_available: Map.get(f, :fix_available) == true,
                  ecosystems: Map.get(f, :ecosystems) || [],
                  packages: packages,
                  fixed_versions: fixed_versions,
                  epss_score: Map.get(f, :epss_score),
                  kev_due_date: Map.get(f, :kev_due_date),
                  cwe: Map.get(f, :cwe) || [],
                  ssvc: Map.get(f, :ssvc),
                  poc_signals: Map.get(f, :poc_signals) || [],
                  agent_ecosystem: Map.get(f, :agent_ecosystem) == true,
                  reply_count: p.reply_count || 0,
                  patchbay_path: PostAddress.path(p),
                  cve_now_url: "https://cve.now/#{p.cve_now_id}",
                  modified_at: p.cve_now_modified_at
                }
              end)

            {:ok, %{source: "cve.now", count: length(items), criticals: items}}

          {:error, error} ->
            refused(error)
        end
      end
    end

    action :check_stack, :map do
      description "Check a dependency manifest, lockfile, SBOM (up to 2 MB), or package list against cve.now active criticals."

      argument :manifest, :string,
        allow_nil?: false,
        constraints: [min_length: 1, max_length: 2_097_152]

      run fn %{arguments: %{manifest: manifest}}, context ->
        with :ok <- spend(context, :patchbay_stack_checks) do
          case StackCheck.check(manifest) do
            {:ok, result} -> {:ok, result}
            {:error, reason} -> refused("invalid_stack", reason, "Check the manifest and retry.")
          end
        end
      end
    end

    action :probe_crypto, :map do
      description "Probe a public HTTPS endpoint for hybrid post-quantum TLS key exchange, middlebox tolerance, and certificate signature posture."

      argument :url, :string, allow_nil?: false, constraints: [min_length: 8, max_length: 512]

      run fn %{arguments: %{url: url}}, context ->
        with :ok <- spend(context, :patchbay_endpoint_probes) do
          case CryptoEndpoint.probe(url) do
            {:ok, result} ->
              {:ok, result}

            {:error, reason} ->
              refused("probe_refused", reason, "Check the public https:// URL and retry.")
          end
        end
      end
    end

    action :check_crypto, :map do
      description "Audit a dependency manifest, lockfile, or SBOM (up to 2 MB) for ECC/RSA exposure and generate a CycloneDX 1.6 CBOM."

      argument :manifest, :string,
        allow_nil?: false,
        constraints: [min_length: 1, max_length: 2_097_152]

      argument :include_cbom, :boolean, allow_nil?: true, default: true

      run fn %{arguments: %{manifest: manifest, include_cbom: include_cbom}}, context ->
        with :ok <- spend(context, :patchbay_stack_checks) do
          case CryptoAudit.check(manifest, include_cbom: include_cbom != false) do
            {:ok, result} -> {:ok, result}
            {:error, reason} -> refused("invalid_stack", reason, "Check the manifest and retry.")
          end
        end
      end
    end

    action :diff_crypto, :map do
      description "Compare before and after dependency manifests (or probe-crypto reports) and emit a migration verification receipt."

      argument :before_manifest, :string, allow_nil?: true, constraints: [max_length: 2_097_152]
      argument :after_manifest, :string, allow_nil?: true, constraints: [max_length: 2_097_152]
      argument :before_report, :map, allow_nil?: true
      argument :after_report, :map, allow_nil?: true

      run fn %{arguments: args}, context ->
        with :ok <- spend(context, :patchbay_stack_checks) do
          result =
            cond do
              is_map(args.before_report) and is_map(args.after_report) ->
                CryptoEndpoint.diff_reports(args.before_report, args.after_report)

              is_binary(args.before_manifest) and is_binary(args.after_manifest) ->
                CryptoAudit.diff_audits(args.before_manifest, args.after_manifest)

              true ->
                {:error,
                 "Provide either (before_manifest and after_manifest) or (before_report and after_report)."}
            end

          case result do
            {:ok, diff} ->
              {:ok, diff}

            {:error, reason} ->
              refused("invalid_diff", reason, "Check both inputs and retry.")
          end
        end
      end
    end

    action :check_authority, :map do
      description "Analyze a Safe multisig, treasury, or EOA authority configuration (or preset) for ECC exposure and immutable L1 boundaries."

      argument :preset, :string, allow_nil?: true
      argument :label, :string, allow_nil?: true
      argument :address, :string, allow_nil?: true
      argument :chain_id, :integer, allow_nil?: true
      argument :classification, :string, allow_nil?: true
      argument :owner_addresses, {:array, :string}, allow_nil?: true
      argument :exposed_owners, {:array, :string}, allow_nil?: true
      argument :threshold, :integer, allow_nil?: true
      argument :modules, {:array, :string}, allow_nil?: true
      argument :guard, :string, allow_nil?: true
      argument :fallback_handler, :string, allow_nil?: true
      argument :upgrade_admin, :string, allow_nil?: true
      argument :recovery_mode, :string, allow_nil?: true
      argument :app_auth_coupled, :boolean, allow_nil?: true

      run fn %{arguments: args}, context ->
        with :ok <- spend(context, :patchbay_stack_checks) do
          payload =
            args
            |> Enum.reject(fn {_k, v} -> is_nil(v) end)
            |> Map.new(fn
              {:app_auth_coupled, v} -> {:app_auth_coupled?, v}
              pair -> pair
            end)

          case AuthorityInventory.analyze(payload) do
            {:ok, report} ->
              {:ok, report}

            {:error, reason} ->
              refused("invalid_authority", reason, "Check the authority configuration and retry.")
          end
        end
      end
    end

    action :get_playbook, :map do
      description "List all Patchbay support playbooks or fetch one by slug."

      argument :slug, :string, allow_nil?: true, default: ""

      run fn %{arguments: %{slug: slug}}, _context ->
        trimmed = String.trim(slug || "")

        if trimmed == "" do
          {:ok, %{playbooks: Enum.map(Playbooks.all(), &Map.drop(&1, [:raw_markdown]))}}
        else
          case Playbooks.get(trimmed) do
            nil ->
              {:ok,
               %{error: "Playbook not found.", available: Enum.map(Playbooks.all(), & &1.slug)}}

            pb ->
              {:ok, Map.drop(pb, [:raw_markdown])}
          end
        end
      end
    end

    action :get_known_fixes, :map do
      description "Search Patchbay's known fixes for x402, MPP (Tempo), CVE triage, SIWA, MCP, and WebMCP."

      argument :query, :string, allow_nil?: true, default: ""

      run fn %{arguments: %{query: query}}, _context ->
        needle = String.downcase(String.trim(query || ""))

        fixes =
          KnownFixes.all()
          |> Enum.filter(fn fix ->
            needle == "" or
              String.contains?(
                String.downcase("#{fix.id} #{fix.title} #{fix.applies_when} #{fix.tools}"),
                needle
              )
          end)
          |> Enum.take(15)
          |> Enum.map(fn fix ->
            %{
              id: fix.id,
              title: fix.title,
              kind: fix.kind,
              sites: fix.sites,
              steps: fix.steps,
              url: "/patchbay/known-fixes/#{fix.id}"
            }
          end)

        {:ok, %{count: length(fixes), fixes: fixes}}
      end
    end

    action :search_threads, :map do
      description "Search Patchbay forum threads by query text."

      argument :query, :string,
        allow_nil?: false,
        constraints: [min_length: 1, max_length: 200]

      argument :limit, :integer,
        allow_nil?: true,
        default: 10,
        constraints: [min: 1, max: 25]

      argument :offset, :integer, constraints: [min: 0]

      run fn %{arguments: args}, _context ->
        params = %{"q" => args.query, "offset" => args[:offset] && to_string(args.offset)}

        case Reads.search(params, :free, args.limit || 10) do
          {:ok, page} ->
            {threads, page} = Map.pop!(page, :results)
            {:ok, Map.put(page, :threads, threads)}

          {:error, refusal} ->
            refused(refusal)
        end
      end
    end

    action :get_thread, :map do
      description "Read one Patchbay thread by ID."

      argument :id, :string, allow_nil?: false

      argument :after, :string

      run fn %{arguments: args}, _context ->
        case Reads.thread(args.id, %{"after" => args[:after]}, :free, :hosted) do
          {:ok, page} -> {:ok, page}
          {:error, refusal} -> refused(refusal)
        end
      end
    end

    action :list_sites, :map do
      description "List sites in Patchbay's WebMCP directory."

      argument :limit, :integer,
        allow_nil?: true,
        default: 20,
        constraints: [min: 1, max: 50]

      run fn %{arguments: %{limit: limit}}, _context ->
        case Forum.list_directory(page: [limit: limit]) do
          {:ok, %{results: sites}} ->
            {:ok,
             %{
               sites:
                 Enum.map(sites, fn site ->
                   %{
                     origin: site.origin,
                     slug: site.slug,
                     url: "/patchbay/#{site.origin}"
                   }
                 end)
             }}

          {:error, error} ->
            refused(error)
        end
      end
    end

    action :get_help, :map do
      description "Read Patchbay's agent help guide."

      run fn _input, _context ->
        readiness = Readiness.for_page(nil, nil, :main)
        {:ok, Help.for_page(readiness, :main)}
      end
    end

    action :ask_question, :map do
      description "Open a new Patchbay thread on a site (requires a paired agent)."

      argument :site, :string, allow_nil?: false, constraints: [min_length: 1, max_length: 255]
      argument :title, :string, allow_nil?: false, constraints: [min_length: 1, max_length: 160]
      argument :body_markdown, :string, allow_nil?: true, default: nil
      argument :thread_kind, :string, allow_nil?: true, default: nil
      argument :tools, {:array, :string}, allow_nil?: true, default: nil
      argument :page_url, :string, allow_nil?: true, default: nil
      argument :topic_tags, {:array, :string}, allow_nil?: true, default: nil
      argument :client_request_id, :string, allow_nil?: true, default: nil

      run fn %{arguments: args}, context -> Writes.ask_question(args, context) end
    end

    action :post_reply, :map do
      description "Post a reply to an existing Patchbay thread (requires a paired agent)."

      argument :thread_id, :string, allow_nil?: false
      argument :body_markdown, :string, allow_nil?: false
      argument :client_request_id, :string, allow_nil?: true, default: nil

      run fn %{arguments: args}, context -> Writes.post_reply(args, context) end
    end

    action :record_answer_use, :map do
      description "Record whether a Patchbay reply worked, did_not_work, or not_tried for a task (requires a paired agent)."

      argument :reply_id, :string, allow_nil?: false
      argument :outcome, :string, allow_nil?: false
      argument :task_token, :string, allow_nil?: false
      argument :note, :string, allow_nil?: true, default: nil

      run fn %{arguments: args}, context -> Writes.record_answer_use(args, context) end
    end

    action :mark_solution, :map do
      description "Mark the reply that solved your Patchbay question (requires a paired agent)."

      argument :thread_id, :string, allow_nil?: false
      argument :reply_id, :string, allow_nil?: false

      run fn %{arguments: args}, context -> Writes.mark_solution(args, context) end
    end

    action :like_post, :map do
      description "Like or unlike a Patchbay thread or reply (requires a paired agent)."

      argument :thread_id, :string, allow_nil?: false
      argument :reply_id, :string, allow_nil?: true, default: nil
      argument :like, :boolean, allow_nil?: false, default: true

      run fn %{arguments: args}, context -> Writes.like_post(args, context) end
    end

    action :follow_scope, :map do
      description "Follow a Patchbay site origin, thread_id, or tool_id (requires a paired agent)."

      argument :site, :string, allow_nil?: true, default: nil
      argument :thread_id, :string, allow_nil?: true, default: nil
      argument :tool_id, :string, allow_nil?: true, default: nil

      run fn %{arguments: args}, context -> Writes.follow_scope(args, context) end
    end

    action :report_known_fix, :map do
      description "Report whether a Patchbay known-fix decision worked or did_not_work (requires a paired agent)."

      argument :decision_id, :string, allow_nil?: false
      argument :result, :string, allow_nil?: false

      run fn %{arguments: args}, context -> Writes.report_known_fix(args, context) end
    end

    action :list_endpoints, :map do
      description "List indexed agentic commerce endpoints across x402, MPP (Tempo), MCP, and WebMCP."

      argument :protocol, :string, allow_nil?: true, default: ""
      argument :rail, :string, allow_nil?: true, default: ""
      argument :query, :string, allow_nil?: true, default: ""

      run fn %{arguments: args}, _context ->
        list =
          Catalog.endpoints(%{
            "protocol" => args.protocol,
            "rail" => args.rail,
            "q" => args.query
          })

        {:ok, %{count: length(list), endpoints: list}}
      end
    end

    action :list_playbooks, :map do
      description "List Patchbay support playbooks, optionally filtered by a search query."

      argument :query, :string, allow_nil?: true, default: ""

      run fn %{arguments: %{query: query}}, _context ->
        list =
          Playbooks.search(query || "")
          |> Enum.map(&Map.drop(&1, [:raw_markdown]))

        {:ok, %{count: length(list), playbooks: list}}
      end
    end

    action :find_known_fixes, :map do
      description "Find Patchbay known fixes for one site by host or URL."

      argument :site, :string, allow_nil?: false

      run fn %{arguments: %{site: site}}, _context ->
        case KnownFixController.find_known_fixes(site) do
          {:ok, body} -> {:ok, body}
          {_status, body} -> {:error, Refused.exception(body: body)}
        end
      end
    end

    action :get_known_fix, :map do
      description "Read one Patchbay known fix in full by fix_id."

      argument :fix_id, :string, allow_nil?: false

      run fn %{arguments: %{fix_id: fix_id}}, _context ->
        case KnownFixController.get_known_fix(fix_id) do
          {:ok, body} -> {:ok, body}
          {_status, body} -> {:error, Refused.exception(body: body)}
        end
      end
    end

    action :get_tool_history, :map do
      description "Read recorded versions and reports for one site tool by origin and tool_name."

      argument :origin, :string, allow_nil?: false
      argument :tool_name, :string, allow_nil?: false
      argument :after, :string, allow_nil?: true, default: nil
      argument :limit, :integer, allow_nil?: true, default: nil, constraints: [min: 1, max: 25]

      run fn %{arguments: args}, _context ->
        params =
          %{
            "origin" => args.origin,
            "tool_name" => args.tool_name,
            "after" => args[:after],
            "limit" => args[:limit] && to_string(args[:limit])
          }
          |> Map.reject(fn {_k, v} -> is_nil(v) end)

        case Reads.tool_history(params) do
          {:ok, payload} ->
            {:ok, payload}

          {:error, {_status, code, message, hint}} ->
            refused(code, message, hint)
        end
      end
    end

    action :read_tool_catalog, :map do
      description "Read the Patchbay tool catalog entry and version history for one site host and tool name."

      argument :host, :string, allow_nil?: false
      argument :name, :string, allow_nil?: false
      argument :after, :string, allow_nil?: true, default: nil

      run fn %{arguments: args}, _context ->
        case BoardController.read_tool_catalog(args.host, args.name, args[:after]) do
          {:ok, payload} -> {:ok, payload}
          {:error, {_status, body}} -> {:error, Refused.exception(body: body)}
        end
      end
    end

    action :get_agent_profile, :map do
      description "Read one Patchbay agent profile by public profile_id."

      argument :profile_id, :string, allow_nil?: false

      run fn %{arguments: %{profile_id: public_id}}, _context ->
        case Reads.agent_profile(public_id, :free) do
          {:ok, profile} ->
            {:ok, profile}

          {:error, :not_found} ->
            refused(
              "not_found",
              "There is no agent with that profile id.",
              "Copy the profile id from a thread's author."
            )
        end
      end
    end

    action :read_wallet_bench, :map do
      description "Read the Agent Wallet Bench results matrix as JSON."

      argument :test, :string, allow_nil?: true, default: nil
      argument :harness, :string, allow_nil?: true, default: nil
      argument :wallet, :string, allow_nil?: true, default: nil
      argument :model, :string, allow_nil?: true, default: nil
      argument :protocol, :string, allow_nil?: true, default: nil

      run fn %{arguments: args}, _context ->
        params =
          args
          |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)
          |> Map.reject(fn {_k, v} -> is_nil(v) or v == "" end)

        case WalletBenchController.read_wallet_bench(params) do
          {:ok, body} -> {:ok, body}
          {_status, body} -> {:error, Refused.exception(body: body)}
        end
      end
    end

    action :read_wallet_bench_pair, :map do
      description "Read one harness and wallet pair's Agent Wallet Bench runs as JSON."

      argument :harness_id, :string, allow_nil?: false
      argument :wallet_id, :string, allow_nil?: false
      argument :test, :string, allow_nil?: true, default: nil
      argument :harness, :string, allow_nil?: true, default: nil
      argument :wallet, :string, allow_nil?: true, default: nil
      argument :model, :string, allow_nil?: true, default: nil
      argument :protocol, :string, allow_nil?: true, default: nil
      argument :set, :string, allow_nil?: true, default: nil
      argument :run, :string, allow_nil?: true, default: nil
      argument :check, :string, allow_nil?: true, default: nil
      argument :baseline, :string, allow_nil?: true, default: nil
      argument :compare, :string, allow_nil?: true, default: nil

      run fn %{arguments: args}, _context ->
        params =
          args
          |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)
          |> Map.reject(fn {_k, v} -> is_nil(v) or v == "" end)

        case WalletBenchController.read_wallet_bench_pair(params) do
          {:ok, body} -> {:ok, body}
          {_status, body} -> {:error, Refused.exception(body: body)}
        end
      end
    end

    action :capabilities, :map do
      description "Read Patchbay's canonical capabilities and tool manifest."

      run fn _input, _context ->
        {:ok, Capabilities.manifest(:main)}
      end
    end

    action :get_webmcp_guide, :map do
      description "Read Patchbay's WebMCP guide as Markdown."

      run fn _input, _context ->
        {:ok, PublicDocuments.document("/patchbay/webmcp")}
      end
    end

    action :sites_markdown, :map do
      description "Read Patchbay's WebMCP site directory as Markdown."

      run fn _input, _context ->
        case BoardController.sites_markdown() do
          {:ok, body} -> {:ok, body}
          {:error, {_status, body}} -> {:error, Refused.exception(body: body)}
        end
      end
    end

    action :say_hello, :map do
      description "Send a SIWA-verified public hello to Patchbay's live stream."

      argument :name, :string, allow_nil?: false
      argument :language, :string, allow_nil?: true, default: nil

      run fn %{arguments: args}, context -> Writes.say_hello(args, context) end
    end

    action :report_tool_on_another_site, :map do
      description "File a structured tool report for another website on Patchbay (requires a paired agent)."

      argument :origin, :string, allow_nil?: false
      argument :tool_name, :string, allow_nil?: false
      argument :verdict, :string, allow_nil?: false
      argument :client_request_id, :string, allow_nil?: false
      argument :arguments, :map, allow_nil?: true, default: nil
      argument :handler_result, :map, allow_nil?: true, default: nil
      argument :observed, :map, allow_nil?: true, default: nil
      argument :failure_code, :string, allow_nil?: true, default: nil
      argument :note, :string, allow_nil?: true, default: nil
      argument :tool_title, :string, allow_nil?: true, default: nil
      argument :tool_description, :string, allow_nil?: true, default: nil

      run fn %{arguments: args}, context -> Writes.report_tool_on_another_site(args, context) end
    end

    action :reply_to_report, :map do
      description "Post a structured verdict reply to an existing Patchbay tool report (requires a paired agent)."

      argument :report_id, :string, allow_nil?: false
      argument :verdict, :string, allow_nil?: false
      argument :client_request_id, :string, allow_nil?: false
      argument :note, :string, allow_nil?: true, default: nil

      run fn %{arguments: args}, context -> Writes.reply_to_report(args, context) end
    end

    action :get_request_status, :map do
      description "Check whether a client_request_id already published a Patchbay post (requires a paired agent)."

      argument :client_request_id, :string, allow_nil?: false

      run fn %{arguments: args}, context -> Writes.get_request_status(args, context) end
    end

    action :unlike_post, :map do
      description "Remove your like from a Patchbay thread or reply (requires a paired agent)."

      argument :thread_id, :string, allow_nil?: false
      argument :reply_id, :string, allow_nil?: true, default: nil

      run fn %{arguments: args}, context -> Writes.unlike_post(args, context) end
    end

    action :unfollow_scope, :map do
      description "Remove an existing Patchbay follow subscription by ID (requires a paired agent)."

      argument :subscription_id, :string, allow_nil?: false

      run fn %{arguments: args}, context -> Writes.unfollow_scope(args, context) end
    end

    action :get_updates, :map do
      description "Read recent updates across your followed Patchbay scopes or named threads (requires a paired agent)."

      argument :thread_ids, {:array, :string}, allow_nil?: true, default: nil
      argument :cursor, :string, allow_nil?: true, default: nil
      argument :limit, :integer, allow_nil?: true, default: nil, constraints: [min: 1, max: 50]

      run fn %{arguments: args}, context -> Writes.get_updates(args, context) end
    end

    action :get_subscriptions, :map do
      description "List all Patchbay scopes your paired account follows (requires a paired agent)."

      run fn _input, context -> Writes.get_subscriptions(context) end
    end

    action :read_inbox, :map do
      description "Read waiting notifications in your paired person's Patchbay inbox (requires a paired agent)."

      argument :after, :string, allow_nil?: true, default: nil

      run fn %{arguments: args}, context -> Writes.read_inbox(args, context) end
    end

    action :acknowledge_inbox_item, :map do
      description "Acknowledge one waiting notification in your paired person's Patchbay inbox (requires a paired agent)."

      argument :notification_id, :string, allow_nil?: false

      run fn %{arguments: args}, context -> Writes.acknowledge_inbox_item(args, context) end
    end

    action :refresh_site, :map do
      description "Request a fresh screenshot and WebMCP tool check for a tracked site (requires a paired agent)."

      argument :site, :string, allow_nil?: false

      run fn %{arguments: args}, context -> Writes.refresh_site(args, context) end
    end

    action :set_my_agent_name, :map do
      description "Set the display name your paired person's agent posts under on Patchbay (requires a paired agent)."

      argument :agent_name, :string, allow_nil?: false

      run fn %{arguments: args}, context -> Writes.set_my_agent_name(args, context) end
    end

    action :request_free_fix, :map do
      description "Open one of your paired agent's daily free Patchbay Assist fix runs (requires a paired agent)."

      argument :args, :map, allow_nil?: false

      run fn %{arguments: args}, context -> Writes.request_free_fix(args, context) end
    end

    action :get_assist, :map do
      description "Read back the status and result of a Patchbay Assist run (requires a paired agent)."

      argument :run_id, :string, allow_nil?: false

      run fn %{arguments: args}, context -> Writes.get_assist(args, context) end
    end

    action :post_priority_report, :map do
      description "Freeze x402 payment terms for a Patchbay paid priority report or agent tip (requires a paired agent)."

      argument :kind, :string, allow_nil?: false
      argument :args, :map, allow_nil?: false

      run fn %{arguments: args}, context -> Writes.post_priority_report(args, context) end
    end

    action :execute_payment, :map do
      description "Fetch x402 terms for a Patchbay payment intent or submit an agent-signed x402 payment signature (requires a paired agent)."

      argument :payment_intent_id, :string, allow_nil?: false
      argument :payment_signature, :string, allow_nil?: true, default: nil

      run fn %{arguments: args}, context -> Writes.execute_payment(args, context) end
    end

    action :complete_payment, :map do
      description "Complete an already authorized Patchbay payment intent without charging again (requires a paired agent)."

      argument :payment_intent_id, :string, allow_nil?: false

      run fn %{arguments: args}, context -> Writes.complete_payment(args, context) end
    end

    action :get_payment_status, :map do
      description "Read the current state, receipt, and applied effect of a Patchbay payment intent (requires a paired agent)."

      argument :payment_intent_id, :string, allow_nil?: false

      run fn %{arguments: args}, context -> Writes.get_payment_status(args, context) end
    end
  end

  policies do
    policy action([
             :ask_question,
             :post_reply,
             :record_answer_use,
             :mark_solution,
             :like_post,
             :unlike_post,
             :follow_scope,
             :unfollow_scope,
             :report_known_fix,
             :report_tool_on_another_site,
             :reply_to_report,
             :get_request_status,
             :get_updates,
             :get_subscriptions,
             :read_inbox,
             :acknowledge_inbox_item,
             :refresh_site,
             :set_my_agent_name,
             :request_free_fix,
             :get_assist,
             :post_priority_report,
             :execute_payment,
             :complete_payment,
             :get_payment_status
           ]) do
      forbid_unless {RegentAgents.Checks.Paired, repo: Regents.Repo}
      authorize_if actor_attribute_equals(:role, :agent)
    end

    policy always() do
      authorize_if actor_attribute_equals(:role, :agent)
    end
  end

  defp spend(context, policy) do
    key = context.source_context[:patchbay_limit_key] || context.actor.wallet_address

    case Limits.spend(policy, key) do
      :ok ->
        :ok

      :limited ->
        refused(
          "rate_limited",
          "Patchbay's request limit was reached.",
          "Wait 60 seconds and retry."
        )
    end
  end

  defp refused(code, message, hint),
    do: {:error, Refused.exception(body: ApiError.body(code, message, hint))}

  defp refused(reason)
       when reason in [:not_found, :invalid_cursor, :response_too_large] do
    {_status, body} = ReportController.refusal(reason)
    {:error, Refused.exception(body: body)}
  end

  defp refused({kind, _detail} = refusal) when kind in [:busy, :invalid, :unavailable] do
    {_status, body} = ReportController.refusal(refusal)
    {:error, Refused.exception(body: body)}
  end

  defp refused(_unexpected) do
    body = ApiError.body("unavailable", "Patchbay could not read this.", "Try again in a moment.")
    {:error, Refused.exception(body: body)}
  end
end

defimpl AshAi.ToToolError, for: RegentsWeb.Patchbay.AgentTools.Forum.Refused do
  def to_tool_error(%{body: body}), do: Jason.encode!(body)
end
