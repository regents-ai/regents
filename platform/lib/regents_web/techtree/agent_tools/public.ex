defmodule RegentsWeb.Techtree.AgentTools.Public do
  @moduledoc """
  Read-only hosted MCP tool actions for Techtree at `/mcp`. Every refusal
  follows Regents' shared `%{error: %{code, message, hint}}` envelope.
  """

  use Ash.Resource,
    domain: RegentsWeb.Techtree.AgentTools,
    authorizers: [Ash.Policy.Authorizer]

  alias Regents.Techtree.Catalog.{Bundle, Digest}
  alias Regents.Techtree.Catalog.Query, as: CatalogQuery
  alias Regents.Techtree.Network.{Projection, Query}
  alias Regents.Techtree.Train.Comparisons
  alias Regents.Techtree.WalletBench.Reading
  alias RegentsWeb.Techtree.{Outage, WalletBenchScores}

  @linked_objects [
    {"climb", "climb_digest"},
    {"campaign", "campaign_spec_digest"},
    {"execution_plan", "execution_plan_digest"},
    {"data_policy", "data_policy_digest"},
    {"taskset_validation", "validation_receipt_digest"}
  ]

  actions do
    action :catalog, :map do
      description "Read the active Techtree catalog of published Climbs and Skills."

      run fn _input, _context ->
        case Outage.read(&CatalogQuery.catalog_bytes/0) do
          {:ok, {:ok, bytes, _digest}} ->
            {:ok, Jason.decode!(bytes)}

          {:ok, {:error, error}} ->
            {:ok, refusal(error.code, error.message, "Retry or check /api/v1/health.")}

          :database_down ->
            {:ok,
             refusal("unavailable", "Techtree catalog is unavailable.", "Try again in a moment.")}
        end
      end
    end

    action :bootstrap, :map do
      description "Read the active Techtree release's CLI bootstrap and install metadata."

      run fn _input, _context ->
        case Outage.read(&CatalogQuery.bootstrap_payload/0) do
          {:ok, {:ok, payload, _digest}} ->
            {:ok, Jason.decode!(payload)}

          {:ok, {:error, error}} ->
            {:ok, refusal(error.code, error.message, "Retry or check /api/v1/health.")}

          :database_down ->
            {:ok,
             refusal(
               "unavailable",
               "Techtree bootstrap is unavailable.",
               "Try again in a moment."
             )}
        end
      end
    end

    action :climb, :map do
      description "Read one published Techtree Climb by slug."

      argument :slug, :string, allow_nil?: false, constraints: [min_length: 1, max_length: 120]

      run fn %{arguments: %{slug: slug}}, _context ->
        case Outage.read(fn -> CatalogQuery.get_climb_by_slug(slug) end) do
          {:ok, {:ok, entry}} ->
            {:ok, climb_projection(entry)}

          {:ok, {:error, error}} ->
            {:ok,
             refusal(
               error.code,
               error.message,
               "Call techtree_catalog to list available Climb slugs."
             )}

          :database_down ->
            {:ok,
             refusal("unavailable", "Techtree catalog is unavailable.", "Try again in a moment.")}
        end
      end
    end

    action :publications, :map do
      description "List published Techtree evaluation Results, newest first."

      argument :limit, :integer, allow_nil?: true, default: 25, constraints: [min: 1, max: 100]
      argument :before_sequence, :integer, allow_nil?: true, constraints: [min: 1]

      run fn %{arguments: args}, _context ->
        params =
          %{"limit" => Integer.to_string(args.limit)}
          |> maybe_put_before(args[:before_sequence])

        with {:ok, options} <- Query.read_page_options(params),
             {:ok, page} <- Outage.read(fn -> Query.page(options) end) do
          bytes = Projection.log(page, RegentsWeb.Endpoint.url())
          {:ok, Jason.decode!(bytes)}
        else
          {:error, message} ->
            {:ok,
             refusal(
               "publication_query_invalid",
               message,
               "Pass integer limit (1..100) and optional before_sequence."
             )}

          :database_down ->
            {:ok,
             refusal("unavailable", "Techtree results are unavailable.", "Try again in a moment.")}
        end
      end
    end

    action :publication_show, :map do
      description "Read one published Techtree Result by bundle digest."

      argument :bundle_digest, :string,
        allow_nil?: false,
        constraints: [min_length: 10, max_length: 120]

      run fn %{arguments: %{bundle_digest: digest}}, _context ->
        if Digest.valid?(digest) do
          read_publication(digest)
        else
          {:ok,
           refusal(
             "publication_digest_invalid",
             "The bundle_digest is not a valid sha256 digest.",
             "Call techtree_publications to list valid bundle digests."
           )}
        end
      end
    end

    action :skill, :map do
      description "Read a published Techtree Skill's files and standing Results by root digest."

      argument :root_digest, :string,
        allow_nil?: false,
        constraints: [min_length: 10, max_length: 120]

      run fn %{arguments: %{root_digest: digest}}, _context ->
        if Digest.valid?(digest) do
          read_skill(digest)
        else
          {:ok,
           refusal(
             "skill_digest_invalid",
             "The root_digest is not a valid sha256 digest.",
             "Use a skill root digest listed on a published Result from techtree_publications."
           )}
        end
      end
    end

    action :wallet_bench, :map do
      description "Read the Agent Wallet Bench score grids."

      run fn _input, _context ->
        case Outage.read(&Reading.reading/0) do
          {:ok, reading} ->
            {:ok, WalletBenchScores.feed(reading)}

          :database_down ->
            {:ok,
             refusal(
               "scores_unavailable",
               "Wallet Bench is unavailable.",
               "Try again in a moment."
             )}
        end
      end
    end

    action :train_comparisons, :map do
      description "List published public Skill comparison demonstrations."

      run fn _input, _context ->
        origin = RegentsWeb.Endpoint.url()

        comparisons =
          Enum.map(Comparisons.list(), fn comparison ->
            comparison
            |> Map.drop([:cases])
            |> Map.merge(%{
              url: origin <> "/techtree/train/" <> comparison.slug,
              report_url: origin <> "/techtree/train/" <> comparison.slug <> "/report.json"
            })
          end)

        {:ok, %{comparisons: comparisons}}
      end
    end

    action :train_report, :map do
      description "Read one published Techtree Train comparison's full per-case JSON report."

      argument :slug, :string, allow_nil?: false, constraints: [min_length: 1, max_length: 120]

      run fn %{arguments: %{slug: slug}}, _context ->
        case Comparisons.download(slug) do
          {:ok, bytes, _digest} ->
            {:ok, Jason.decode!(bytes)}

          :error ->
            {:ok,
             refusal(
               "comparison_not_found",
               "No Train comparison has that slug.",
               "Call techtree_train_comparisons to list available comparison slugs."
             )}
        end
      end
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  defp read_publication(digest) do
    case Outage.read(fn -> fetch_entry_with_runs(digest) end) do
      {:ok, {:ok, entry, runs_behind}} ->
        bytes = Projection.entry(entry, runs_behind, RegentsWeb.Endpoint.url())
        {:ok, Jason.decode!(bytes)}

      {:ok, :error} ->
        {:ok,
         refusal(
           "publication_missing",
           "No published Result has that bundle digest.",
           "Call techtree_publications to list available bundle digests."
         )}

      :database_down ->
        {:ok,
         refusal("unavailable", "Techtree results are unavailable.", "Try again in a moment.")}
    end
  end

  defp fetch_entry_with_runs(digest) do
    with {:ok, entry} <- Query.get_entry(digest) do
      {:ok, entry, Query.runs_behind(entry)}
    end
  end

  defp read_skill(digest) do
    case Outage.read(fn -> Query.skill(digest) end) do
      {:ok, {:ok, answer}} ->
        bytes = Projection.skill(answer)
        {:ok, Jason.decode!(bytes)}

      {:ok, :error} ->
        {:ok,
         refusal(
           "skill_not_found",
           "No standing published Result carries that Skill digest.",
           "Call techtree_publications to find published Skills."
         )}

      :database_down ->
        {:ok,
         refusal("unavailable", "Techtree skills are unavailable.", "Try again in a moment.")}
    end
  end

  defp refusal(code, message, hint),
    do: %{error: %{code: to_string(code), message: message, hint: hint}}

  defp maybe_put_before(params, nil), do: params

  defp maybe_put_before(params, seq) when is_integer(seq),
    do: Map.put(params, "before_sequence", Integer.to_string(seq))

  defp climb_projection(entry) do
    objects =
      @linked_objects
      |> Map.new(fn {name, key} -> {name, linked_object(Map.fetch!(entry.projection, key))} end)
      |> maybe_put_held_out(entry.projection["held_out_campaign_spec_digest"])

    entry.projection
    |> Map.put("kind", "climb_summary_projection")
    |> Map.put("objects", objects)
  end

  defp maybe_put_held_out(objects, nil), do: objects

  defp maybe_put_held_out(objects, digest),
    do: Map.put(objects, "held_out_campaign", linked_object(digest))

  defp linked_object(digest) do
    %{
      "digest" => digest,
      "media_type" => Bundle.json_media_type(),
      "url" => "/api/v1/techtree/objects/" <> digest
    }
  end
end
