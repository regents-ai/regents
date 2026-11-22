defmodule RegentsWeb.Patchbay.AgentTools.Forum do
  @moduledoc """
  Hosted MCP tool actions for Patchbay's forum reads, available to paired agents
  at `/mcp`.
  """
  use Ash.Resource,
    domain: RegentsWeb.Patchbay.AgentTools,
    authorizers: [Ash.Policy.Authorizer]

  alias Regents.Account.Actors.Agent
  alias Regents.Patchbay.Forum
  alias RegentsWeb.Patchbay.Forum.Help

  actions do
    action :search_threads, :map do
      description "Search Patchbay forum threads by query text."

      argument :query, :string,
        allow_nil?: false,
        constraints: [min_length: 1, max_length: 200]

      argument :limit, :integer,
        allow_nil?: true,
        default: 10,
        constraints: [min: 1, max: 25]

      run fn %{arguments: %{query: query, limit: limit}}, _context ->
        case Forum.search_reports(query, page: [limit: limit]) do
          {:ok, %{results: reports}} ->
            {:ok,
             %{
               threads:
                 Enum.map(reports, fn report ->
                   %{
                     id: report.id,
                     title: report.title,
                     kind: to_string(report.kind),
                     status: to_string(report.status),
                     url: "/patchbay/threads/#{report.id}"
                   }
                 end)
             }}

          {:error, error} ->
            {:error, error}
        end
      end
    end

    action :get_thread, :map do
      description "Read one Patchbay thread by ID."

      argument :id, :string, allow_nil?: false

      run fn %{arguments: %{id: id}}, _context ->
        case Forum.get_report(id, load: [:replies]) do
          {:ok, report} ->
            {:ok,
             %{
               id: report.id,
               title: report.title,
               body: report.body,
               kind: to_string(report.kind),
               status: to_string(report.status),
               url: "/patchbay/threads/#{report.id}",
               replies:
                 Enum.map(report.replies || [], fn reply ->
                   %{id: reply.id, body: reply.body, inserted_at: reply.inserted_at}
                 end)
             }}

          {:error, error} ->
            {:error, error}
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
                     url: "/patchbay/#{site.slug}"
                   }
                 end)
             }}

          {:error, error} ->
            {:error, error}
        end
      end
    end

    action :get_help, :map do
      description "Read Patchbay's agent help guide."

      run fn _input, _context ->
        {:ok, Help.payload()}
      end
    end
  end

  policies do
    policy always() do
      authorize_if fn %{actor: actor}, _ctx -> match?(%Agent{pairing: %_{}}, actor) end
    end
  end
end
