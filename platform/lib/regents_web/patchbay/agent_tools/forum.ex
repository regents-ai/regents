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
  alias Regents.Patchbay.Forum.PostAddress
  alias Regents.Patchbay.Playbooks
  alias Regents.Patchbay.Probes.PaymentEndpoint
  alias Regents.Patchbay.Security.StackCheck
  alias RegentsWeb.Patchbay.AgentTools.Writes
  alias RegentsWeb.Patchbay.ApiError
  alias RegentsWeb.Patchbay.Forum.Readiness
  alias RegentsWeb.Patchbay.ForumAPI.{Reads, ReportController}
  alias RegentsWeb.Patchbay.Help
  alias RegentsWeb.Patchbay.OffersController

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

      run fn %{arguments: %{url: url, method: method}}, context ->
        with :ok <- spend(context, :patchbay_endpoint_probes) do
          case PaymentEndpoint.probe(url, method) do
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
                f = p.cve_facts

                %{
                  id: p.cve_now_id,
                  title: p.title,
                  product: f && f.product,
                  severity: f && f.severity,
                  score: f && f.score,
                  exploited: (f && f.exploited) || false,
                  fix_available: (f && f.fix_available) || false,
                  ecosystems: (f && f.ecosystems) || [],
                  reply_count: p.reply_count || 0,
                  patchbay_path: PostAddress.path(p),
                  cve_now_url: "https://cve.now/#{p.cve_now_id}"
                }
              end)

            {:ok, %{source: "cve.now", count: length(items), criticals: items}}

          {:error, error} ->
            refused(error)
        end
      end
    end

    action :check_stack, :map do
      description "Check a dependency manifest or comma-separated package list against cve.now active criticals."

      argument :manifest, :string,
        allow_nil?: false,
        constraints: [min_length: 1, max_length: 65_536]

      run fn %{arguments: %{manifest: manifest}}, context ->
        with :ok <- spend(context, :patchbay_stack_checks) do
          case StackCheck.check(manifest) do
            {:ok, result} -> {:ok, result}
            {:error, reason} -> refused("invalid_stack", reason, "Check the manifest and retry.")
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
  end

  policies do
    policy action([
             :ask_question,
             :post_reply,
             :record_answer_use,
             :mark_solution,
             :like_post,
             :follow_scope,
             :report_known_fix
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
