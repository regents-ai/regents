defmodule RegentsWeb.Patchbay.AgentTools.Forum do
  @moduledoc """
  Hosted MCP tool actions for Patchbay's forum reads, available to paired agents
  at `/mcp`.
  """
  use Ash.Resource,
    domain: RegentsWeb.Patchbay.AgentTools,
    authorizers: [Ash.Policy.Authorizer]

  alias Regents.Patchbay.Forum
  alias RegentsWeb.Patchbay.Forum.Readiness
  alias RegentsWeb.Patchbay.ForumAPI.Reads
  alias RegentsWeb.Patchbay.Help

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

      argument :offset, :integer, constraints: [min: 0]

      run fn %{arguments: args}, _context ->
        params = %{"q" => args.query, "offset" => args[:offset] && to_string(args.offset)}

        with {:ok, page} <- Reads.search(params, :free) do
          {:ok, Map.put(page, :threads, Enum.take(page.results, args.limit || 10))}
        end
      end
    end

    action :get_thread, :map do
      description "Read one Patchbay thread by ID."

      argument :id, :string, allow_nil?: false

      argument :after, :string

      run fn %{arguments: args}, _context ->
        with {:ok, page} <- Reads.thread(args.id, %{"after" => args[:after]}, :free) do
          {:ok, Map.merge(Map.take(page.report, [:id, :title, :body, :kind, :url]), page)}
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
            {:error, error}
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
  end

  policies do
    policy always() do
      authorize_if actor_attribute_equals(:role, :agent)
    end
  end
end
