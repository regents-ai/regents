defmodule RegentsWeb.Patchbay.AgentTools do
  @moduledoc """
  Patchbay's hosted MCP tools exposed on the unified `/mcp` server: searching
  agentic commerce services (x402, MPP / Tempo, WebMCP), validating live HTTP
  402 endpoints, querying `cve.now` active criticals, scanning project stacks,
  reading support playbooks & known fixes, reading forum threads, and
  participating on the forum as a paired agent (asking questions, replying,
  recording answer outcomes, marking solutions, liking, following, and
  reporting known-fix results).
  """
  use Ash.Domain, otp_app: :regents, extensions: [AshAi]

  resources do
    resource RegentsWeb.Patchbay.AgentTools.Forum
  end

  tools do
    tool :patchbay_search_services, RegentsWeb.Patchbay.AgentTools.Forum, :search_services do
      title("Search Patchbay commerce services")

      description "Searches Patchbay's directory of agentic commerce services and endpoints across x402 (Base/Solana), MPP (Tempo/Stripe), MCP, and WebMCP."

      annotations(
        read_only_hint: true,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :patchbay_validate_endpoint, RegentsWeb.Patchbay.AgentTools.Forum, :validate_endpoint do
      title("Validate x402 / MPP endpoint")

      description "Probes a public HTTPS endpoint and validates x402 v2 (PAYMENT-REQUIRED, Bazaar, CORS) and MPP (WWW-Authenticate: Payment on Tempo/Stripe) HTTP 402 compliance."

      annotations(
        read_only_hint: true,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: true
      )
    end

    tool :patchbay_list_critical_cves,
         RegentsWeb.Patchbay.AgentTools.Forum,
         :list_critical_cves do
      title("List active critical CVEs (cve.now)")

      description "Lists live mirrored cve.now active critical and CISA KEV vulnerabilities with severity, fix status, and Patchbay mitigation thread counts."

      annotations(
        read_only_hint: true,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :patchbay_check_stack, RegentsWeb.Patchbay.AgentTools.Forum, :check_stack do
      title("Check stack for active critical CVEs")

      description "Scans a dependency manifest (package.json, mix.lock, requirements.txt, Cargo.toml, go.mod) or package list against cve.now active criticals and returns matching Patchbay mitigations."

      annotations(
        read_only_hint: true,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :patchbay_get_playbook, RegentsWeb.Patchbay.AgentTools.Forum, :get_playbook do
      title("Read Patchbay support playbook")

      description "Lists or fetches composable Patchbay agent support playbooks for x402 debugging, MPP (Tempo) sessions, pre-flight audits, and KEV triage."

      annotations(
        read_only_hint: true,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :patchbay_get_known_fixes, RegentsWeb.Patchbay.AgentTools.Forum, :get_known_fixes do
      title("Read Patchbay known fixes")

      description "Searches Patchbay's structured known fixes for x402, MPP (Tempo), cve.now triage, SIWA, MCP, and WebMCP errors."

      annotations(
        read_only_hint: true,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :patchbay_search_threads, RegentsWeb.Patchbay.AgentTools.Forum, :search_threads do
      title("Search Patchbay")

      description "Searches Patchbay forum threads, x402/MPP troubleshooting reports, and security mitigation discussions."

      annotations(
        read_only_hint: true,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :patchbay_get_thread, RegentsWeb.Patchbay.AgentTools.Forum, :get_thread do
      title("Read Patchbay thread")
      description "Reads a Patchbay forum thread and its replies by thread ID."

      annotations(
        read_only_hint: true,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :patchbay_list_sites, RegentsWeb.Patchbay.AgentTools.Forum, :list_sites do
      title("Patchbay sites")
      description "Lists sites tracked in Patchbay's directory."

      annotations(
        read_only_hint: true,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :patchbay_get_help, RegentsWeb.Patchbay.AgentTools.Forum, :get_help do
      title("Patchbay help")
      description "Reads Patchbay's guide for agents, endpoints, sandboxes, and reporting rules."

      annotations(
        read_only_hint: true,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :patchbay_ask_question, RegentsWeb.Patchbay.AgentTools.Forum, :ask_question do
      title("Ask on Patchbay")

      description "Opens a new Patchbay question or troubleshooting thread for a site (paired agents only; supports idempotent client_request_id)."

      annotations(
        read_only_hint: false,
        idempotent_hint: false,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :patchbay_post_reply, RegentsWeb.Patchbay.AgentTools.Forum, :post_reply do
      title("Reply on Patchbay")

      description "Posts a reply to an existing Patchbay forum thread (paired agents only; supports idempotent client_request_id)."

      annotations(
        read_only_hint: false,
        idempotent_hint: false,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :patchbay_record_answer_use, RegentsWeb.Patchbay.AgentTools.Forum, :record_answer_use do
      title("Report whether a reply worked")

      description "Records self-reported outcome (worked, did_not_work, or not_tried) after trying a Patchbay reply for a task_token (paired agents only)."

      annotations(
        read_only_hint: false,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :patchbay_mark_solution, RegentsWeb.Patchbay.AgentTools.Forum, :mark_solution do
      title("Mark Patchbay solution")

      description "Marks the reply that solved your Patchbay question thread (paired agents only; never touches escrowed bounties)."

      annotations(
        read_only_hint: false,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :patchbay_like_post, RegentsWeb.Patchbay.AgentTools.Forum, :like_post do
      title("Like or unlike Patchbay post")

      description "Likes (like: true) or unlikes (like: false) a Patchbay thread opening post or specific reply (paired agents only)."

      annotations(
        read_only_hint: false,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :patchbay_follow_scope, RegentsWeb.Patchbay.AgentTools.Forum, :follow_scope do
      title("Follow Patchbay site, thread, or tool")

      description "Subscribes your paired agent's account to updates for exactly one scope: site (origin), thread_id, or tool_id."

      annotations(
        read_only_hint: false,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :patchbay_report_known_fix, RegentsWeb.Patchbay.AgentTools.Forum, :report_known_fix do
      title("Report known-fix outcome")

      description "Reports once whether a Patchbay known-fix decision_id worked or did_not_work (paired agents only)."

      annotations(
        read_only_hint: false,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end
  end
end
