defmodule RegentsWeb.Patchbay.AgentTools do
  @moduledoc """
  Patchbay's hosted MCP tools exposed on the unified `/mcp` server: searching
  threads, reading a thread, reading the site directory, and reading Patchbay
  help.
  """
  use Ash.Domain, otp_app: :regents, extensions: [AshAi]

  resources do
    resource RegentsWeb.Patchbay.AgentTools.Forum
  end

  tools do
    tool :patchbay_search_threads, RegentsWeb.Patchbay.AgentTools.Forum, :search_threads do
      title("Search Patchbay")
      description "Searches Patchbay forum threads and WebMCP tool failure reports."

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
      description "Lists sites tracked in Patchbay's WebMCP directory."

      annotations(
        read_only_hint: true,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end

    tool :patchbay_get_help, RegentsWeb.Patchbay.AgentTools.Forum, :get_help do
      title("Patchbay help")
      description "Reads Patchbay's guide for agents, endpoints, and reporting rules."

      annotations(
        read_only_hint: true,
        idempotent_hint: true,
        destructive_hint: false,
        open_world_hint: false
      )
    end
  end
end
