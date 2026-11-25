defmodule RegentsWeb.Patchbay.AgentTools.Forum do
  @moduledoc """
  Hosted MCP tool actions for Patchbay's forum reads, available to paired agents
  at `/mcp`.
  """
  use Ash.Resource,
    domain: RegentsWeb.Patchbay.AgentTools,
    authorizers: [Ash.Policy.Authorizer]

  alias Regents.Patchbay.Forum
  alias RegentsWeb.Patchbay.ApiError
  alias RegentsWeb.Patchbay.Forum.Readiness
  alias RegentsWeb.Patchbay.ForumAPI.{Reads, ReportController}
  alias RegentsWeb.Patchbay.Help

  defmodule Refused do
    @moduledoc false
    use Splode.Error, fields: [:body], class: :invalid

    def message(%{body: %{error: %{message: message}}}), do: message
  end

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
  end

  policies do
    policy always() do
      authorize_if actor_attribute_equals(:role, :agent)
    end
  end

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
